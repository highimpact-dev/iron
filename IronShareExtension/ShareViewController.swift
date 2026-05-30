import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

@MainActor
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        Task {
            await importSharedPDF()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        statusLabel.text = "Reading FitProfile report..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func importSharedPDF() async {
        do {
            statusLabel.text = "Preparing FitProfile report..."
            let media = try await firstSharedFitProfileMedia()
            try storeMediaForImport(media)
            statusLabel.text = "Opening Iron..."
            openIron(FitProfileReport.importURL)
        } catch {
            showStatus(error.localizedDescription)
        }
    }

    private func firstSharedFitProfileMedia() async throws -> FitProfileImportMedia {
        let attachments = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []

        if let imageProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            return try await dataRepresentation(
                from: imageProvider,
                typeIdentifier: UTType.image.identifier,
                mimeType: "image/png"
            )
        }

        guard let pdfProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) else {
            throw FitProfileShareError.missingReport
        }
        let pdfMedia = try await dataRepresentation(
            from: pdfProvider,
            typeIdentifier: UTType.pdf.identifier,
            mimeType: "application/pdf"
        )
        guard let imageData = firstPagePNGData(fromPDFData: pdfMedia.data) else {
            return pdfMedia
        }
        return FitProfileImportMedia(mimeType: "image/png", data: imageData)
    }

    private func dataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        mimeType: String
    ) async throws -> FitProfileImportMedia {
        let providerBox = SendableProviderBox(provider)
        return try await withCheckedThrowingContinuation { continuation in
            let box = TimedContinuationBox(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                box.resume(throwing: FitProfileShareError.timedOut("Loading the shared FitProfile report took too long. Try sharing it again."))
            }

            providerBox.provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                if let data {
                    box.resume(returning: FitProfileImportMedia(mimeType: mimeType, data: data))
                    return
                }

                providerBox.provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    if let error {
                        box.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        box.resume(throwing: FitProfileShareError.missingReport)
                        return
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        box.resume(returning: FitProfileImportMedia(mimeType: mimeType, data: data))
                    } catch {
                        box.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func firstPagePNGData(fromPDFData data: Data) -> Data? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        return image.pngData()
    }

    private func openIron(_ url: URL) {
        extensionContext?.open(url) { [weak self] didOpen in
            Task { @MainActor in
                if didOpen {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    self?.showStatus("Opening Iron...")
                    self?.openIronFromResponderChain(url)
                }
            }
        }
    }

    private func openIronFromResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let application = currentResponder as? UIApplication {
                application.open(url, options: [:]) { [weak self] didOpen in
                    Task { @MainActor in
                        if didOpen {
                            self?.extensionContext?.completeRequest(returningItems: nil)
                        } else {
                            self?.showStatus("Iron could not be opened from the share sheet.")
                        }
                    }
                }
                return
            }
            responder = currentResponder.next
        }
        showStatus("Iron could not be opened from the share sheet.")
    }

    private func storeMediaForImport(_ media: FitProfileImportMedia) throws {
        let data = try JSONEncoder().encode(media)
        UIPasteboard.general.setData(data, forPasteboardType: FitProfileReport.mediaPasteboardType)
    }

    private func showStatus(_ message: String) {
        statusLabel.text = message
    }
}

private final class SendableProviderBox: @unchecked Sendable {
    let provider: NSItemProvider

    init(_ provider: NSItemProvider) {
        self.provider = provider
    }
}

private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    timeoutError: Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let box = TimedContinuationBox(continuation)
        let task = Task.detached(priority: .userInitiated) {
            do {
                box.resume(returning: try await operation())
            } catch {
                box.resume(throwing: error)
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) {
            task.cancel()
            box.resume(throwing: timeoutError)
        }
    }
}

private final class TimedContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

private func writeTemporaryPDF(data: Data) throws -> URL {
    let destination = temporaryPDFURL()
    try data.write(to: destination, options: .atomic)
    return destination
}

private func copyTemporaryPDF(from url: URL) throws -> URL {
    let destination = temporaryPDFURL()
    try FileManager.default.copyItem(at: url, to: destination)
    return destination
}

private func temporaryPDFURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("fitprofile-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
}

private enum FitProfileShareError: LocalizedError {
    case missingReport
    case unrecognizedReport
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingReport:
            return "Share a FitProfile PDF or image with Iron."
        case .unrecognizedReport:
            return "Iron could not read this FitProfile report."
        case .timedOut(let message):
            return message
        }
    }
}

private enum FitProfilePDFTextExtractor {
    static func text(from url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw FitProfileShareError.unrecognizedReport
        }

        var textParts: [String] = []
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textParts.append(text)
            } else if let image = image(for: page) {
                textParts.append(try await recognizedText(from: image))
            }
        }
        return textParts.joined(separator: "\n")
    }

    private static func image(for page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 1.25
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
        return image.cgImage
    }

    private static func recognizedText(from image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let box = TimedContinuationBox(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        box.resume(throwing: error)
                        return
                    }
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n") ?? ""
                    box.resume(returning: text)
                }
                request.recognitionLevel = .fast
                request.recognitionLanguages = ["en-US"]
                request.usesLanguageCorrection = false

                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    box.resume(throwing: error)
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10) {
                box.resume(throwing: FitProfileShareError.timedOut("Reading one page of the FitProfile report took too long. Try sharing the PDF again."))
            }
        }
    }
}
