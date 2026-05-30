import AVFoundation
import Combine
import Foundation

enum MealAudioRecorderError: LocalizedError {
    case permissionDenied
    case noRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is required to speak a meal."
        case .noRecording:
            return "No active meal recording was found."
        }
    }
}

@MainActor
final class MealAudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() async throws {
        guard !isRecording else { return }
        guard await requestRecordPermission() else {
            throw MealAudioRecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iron-meal-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        recorder.record()

        self.recorder = recorder
        self.recordingURL = url
        self.isRecording = true
    }

    func stop() throws -> URL {
        guard let recorder, let recordingURL else {
            throw MealAudioRecorderError.noRecording
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        self.isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return recordingURL
    }

    func cancel() {
        recorder?.stop()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
