import SwiftUI
import SwiftData
import WebKit

struct ProgramDayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let day: ProgramDay
    let onStart: (Workout) -> Void
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }, sort: \Exercise.name)
    private var exercises: [Exercise]

    private var orderedExercises: [ProgramExercise] {
        day.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    var body: some View {
        List {
            Section("Day plan") {
                ForEach(orderedExercises) { pe in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pe.exercise?.name ?? "—")
                                .font(.body)
                            Text(targetText(pe))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgramExerciseMetadata(programExercise: pe)
                            ProgramExerciseNotes(
                                notes: pe.notes,
                                videoURLString: videoURLString(for: pe),
                                description: exerciseDescription(for: pe)
                            )
                            SubstitutionMenu(
                                programExercise: pe,
                                exercises: exercises,
                                isDisabled: false,
                                onSelect: { selected in
                                    pe.preferredExercise = selected
                                    try? modelContext.save()
                                }
                            )
                        }
                        Spacer()
                    }
                }
            }

            if let notes = day.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    let workout = Workout(
                        startedAt: Date(),
                        name: day.name,
                        sourceProgram: day.program,
                        sourceProgramDay: day
                    )
                    onStart(workout)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(day.name)
    }

    private func targetText(_ pe: ProgramExercise) -> String {
        let reps: String
        if pe.targetRepsMin == pe.targetRepsMax {
            reps = "\(pe.targetRepsMin)"
        } else {
            reps = "\(pe.targetRepsMin)–\(pe.targetRepsMax)"
        }
        var parts = ["\(pe.targetSets) × \(reps)"]
        if let rir = pe.targetRIR {
            parts.append("\(rir) RIR")
        }
        parts.append(restText(pe.restSeconds))
        return parts.joined(separator: " · ")
    }

    private func restText(_ seconds: Int) -> String {
        if seconds == 120 { return "2 min rest" }
        if seconds >= 180 && seconds <= 300 { return "3-5 min rest" }
        return "\(seconds)s rest"
    }

    private func videoURLString(for pe: ProgramExercise) -> String? {
        guard let preferred = pe.preferredExercise else {
            return pe.videoURLString ?? pe.exercise?.videoURL?.absoluteString
        }

        if preferred.name == pe.substitutionOption1Name {
            return pe.substitutionOption1URLString ?? preferred.videoURL?.absoluteString
        }
        if preferred.name == pe.substitutionOption2Name {
            return pe.substitutionOption2URLString ?? preferred.videoURL?.absoluteString
        }
        return preferred.videoURL?.absoluteString
    }

    private func exerciseDescription(for pe: ProgramExercise) -> String? {
        (pe.preferredExercise ?? pe.exercise)?.instructions
    }
}

struct ProgramExerciseNotes: View {
    let notes: String?
    var videoURLString: String? = nil
    var description: String? = nil
    @State private var videoTarget: ExerciseVideoTarget?

    private var parsedNotes: (url: URL?, text: String?) {
        guard let notes, !notes.isEmpty else { return (nil, nil) }
        let lines = notes.components(separatedBy: .newlines)
        let urlString = lines.first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        let text = lines
            .filter { $0 != urlString }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (urlString.flatMap(URL.init(string:)), text.isEmpty ? nil : text)
    }

    var body: some View {
        let parsed = parsedNotes
        let url = videoURLString.flatMap(URL.init(string:)) ?? parsed.url
        if url != nil || parsed.text != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let url {
                    Button {
                        videoTarget = ExerciseVideoTarget(sourceURL: url)
                    } label: {
                        Label("Watch video", systemImage: "play.circle")
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let text = parsed.text {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
            .fullScreenCover(item: $videoTarget) { target in
                ExerciseVideoPlayerView(target: target)
            }
        }
    }
}

struct ExerciseVideoTarget: Identifiable {
    let sourceURL: URL

    var id: String { sourceURL.absoluteString }

    var embeddedVimeoURL: URL? {
        ExerciseVideoURLBuilder.embeddedURL(for: sourceURL)
    }

    var playerURL: URL {
        embeddedVimeoURL ?? sourceURL
    }
}

private enum ExerciseVideoURLBuilder {
    static func embeddedURL(for url: URL) -> URL? {
        guard let host = url.host(percentEncoded: false)?.lowercased(),
              host.contains("vimeo.com"),
              let videoID = vimeoVideoID(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.vimeo.com"
        components.path = "/video/\(videoID)"

        var queryItems = [URLQueryItem(name: "playsinline", value: "1")]
        if let hash = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "h" })?
            .value {
            queryItems.append(URLQueryItem(name: "h", value: hash))
        }
        components.queryItems = queryItems

        return components.url
    }

    private static func vimeoVideoID(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }

        if let videoIndex = components.firstIndex(of: "video"),
           components.indices.contains(videoIndex + 1),
           components[videoIndex + 1].allSatisfy(\.isNumber) {
            return components[videoIndex + 1]
        }

        return components.first(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    }
}

struct ExerciseVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let target: ExerciseVideoTarget

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ExerciseVideoWebView(target: target)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Exercise video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: target.sourceURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open in browser")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

private enum ExerciseVideoHTMLBuilder {
    static func html(for url: URL) -> String {
        let source = htmlEscaped(url.absoluteString)
        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>
                html, body {
                    background: #000;
                    height: 100%;
                    margin: 0;
                    overflow: hidden;
                    padding: 0;
                    width: 100%;
                }
                body {
                    align-items: center;
                    display: flex;
                    justify-content: center;
                }
                .player {
                    aspect-ratio: 16 / 9;
                    background: #000;
                    max-width: 100vw;
                    position: relative;
                    width: 100vw;
                }
                iframe {
                    background: #000;
                    border: 0;
                    height: 100%;
                    inset: 0;
                    position: absolute;
                    width: 100%;
                }
            </style>
        </head>
        <body>
            <div class="player">
                <iframe src="\(source)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
            </div>
        </body>
        </html>
        """
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct ExerciseVideoWebView: UIViewRepresentable {
    let target: ExerciseVideoTarget

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.indicatorStyle = .white
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedTargetID != target.id else { return }

        if let embeddedURL = target.embeddedVimeoURL {
            webView.loadHTMLString(
                ExerciseVideoHTMLBuilder.html(for: embeddedURL),
                baseURL: URL(string: "https://player.vimeo.com")
            )
        } else {
            webView.load(URLRequest(url: target.playerURL))
        }

        context.coordinator.loadedTargetID = target.id
    }

    final class Coordinator {
        var loadedTargetID: String?
    }
}

struct ProgramExerciseMetadata: View {
    let programExercise: ProgramExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let early = programExercise.earlySetTargetRPE, let last = programExercise.lastSetTargetRPE {
                Text("RPE: early \(early), last \(last)")
            } else if let target = programExercise.targetRPE {
                Text("Target RPE: \(formatNumber(target))")
            }
            if let targetRIR = programExercise.targetRIR {
                Text("Target RIR: \(targetRIR)")
            }

            if let technique = programExercise.intensityTechnique {
                Text("Technique: \(technique)")
            }

            if let substitutions {
                Text("Substitutions: \(substitutions)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var substitutions: String? {
        let names = [
            programExercise.substitutionOption1Name,
            programExercise.substitutionOption2Name,
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        return names.isEmpty ? nil : names.joined(separator: " / ")
    }

    private func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
