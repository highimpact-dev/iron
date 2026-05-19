import SwiftUI
import SwiftData

struct BodyView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthKitPreferenceKeys.readBodyMetrics) private var readHealthBodyMetrics = false

    @Query(
        filter: #Predicate<BodyMetric> { $0.deletedAt == nil },
        sort: \BodyMetric.loggedAt,
        order: .reverse
    )
    private var bodyMetrics: [BodyMetric]

    @Query(
        filter: #Predicate<Workout> { $0.finishedAt != nil && $0.deletedAt == nil },
        sort: \Workout.finishedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    @State private var activeSheet: BodySheet?
    @State private var pendingDelete: BodyMetric?
    @State private var isImportingHealth = false
    @State private var healthImportMessage: String?
    @State private var healthImportError: String?

    private enum BodySheet: Identifiable {
        case addEntry

        var id: String { "add-entry" }
    }

    private var bodyweightSamples: [BodyweightSample] {
        let manual = bodyMetrics.compactMap { metric -> BodyweightSample? in
            guard let weight = metric.bodyweightLb else { return nil }
            return BodyweightSample(date: metric.loggedAt, weight: weight, source: "Body")
        }
        let workoutSamples = workouts.compactMap { workout -> BodyweightSample? in
            guard let weight = workout.bodyweightLb else { return nil }
            return BodyweightSample(date: workout.finishedAt ?? workout.startedAt, weight: weight, source: "Workout")
        }
        return (manual + workoutSamples).sorted { $0.date > $1.date }
    }

    private var latestMetric: BodyMetric? {
        bodyMetrics.first
    }

    private var latestBodyweight: BodyweightSample? {
        bodyweightSamples.first
    }

    private var previousBodyweight: BodyweightSample? {
        guard bodyweightSamples.count > 1 else { return nil }
        return bodyweightSamples[1]
    }

    private var prSnapshots: [PRSnapshot] {
        let workingSets = workouts
            .flatMap(\.setEntries)
            .filter { $0.setType != .warmup && $0.weightLb != nil && $0.reps > 0 }

        let grouped = Dictionary(grouping: workingSets) { $0.exercise?.id ?? UUID() }
        return grouped.compactMap { _, sets -> PRSnapshot? in
            guard let best = sets.max(by: { estimatedOneRepMax($0) < estimatedOneRepMax($1) }),
                  let exercise = best.exercise,
                  let weight = best.weightLb else {
                return nil
            }
            return PRSnapshot(
                id: exercise.id,
                exerciseName: exercise.name,
                estimatedOneRepMax: estimatedOneRepMax(best),
                weight: weight,
                reps: best.reps,
                achievedAt: best.completedAt
            )
        }
        .sorted { $0.estimatedOneRepMax > $1.estimatedOneRepMax }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BodySummaryView(
                        latestBodyweight: latestBodyweight,
                        previousBodyweight: previousBodyweight,
                        latestMetric: latestMetric
                    )
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section("Health") {
                    if HealthKitService.isAvailable {
                        Button {
                            Task { await importHealthBodyMetrics() }
                        } label: {
                            Label(
                                isImportingHealth ? "Importing from Health..." : "Import body metrics",
                                systemImage: "heart.fill"
                            )
                        }
                        .disabled(isImportingHealth || !readHealthBodyMetrics)

                        if let healthImportMessage {
                            Text(healthImportMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !readHealthBodyMetrics {
                            Text("Turn on Health body metric reading in Settings to import weight, body fat, and waist.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Health is unavailable on this device.", systemImage: "heart.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                if bodyweightSamples.count >= 2 {
                    Section("Bodyweight Trend") {
                        BodyweightTrendView(samples: Array(bodyweightSamples.prefix(12)).reversed())
                            .frame(height: 88)
                            .padding(.vertical, 6)
                    }
                }

                Section("Measurements") {
                    if let latestMetric, latestMetric.hasMeasurements {
                        MeasurementGrid(metric: latestMetric)
                    } else {
                        ContentUnavailableView(
                            "No measurements",
                            systemImage: "ruler",
                            description: Text("Add waist, chest, biceps, forearm, thigh, calf, and hip measurements.")
                        )
                    }
                }

                Section("Recent Entries") {
                    if bodyMetrics.isEmpty {
                        Button {
                            activeSheet = .addEntry
                        } label: {
                            Label("Add body entry", systemImage: "plus.circle.fill")
                        }
                    } else {
                        ForEach(bodyMetrics.prefix(10)) { metric in
                            BodyMetricRow(metric: metric)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = metric
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section("Strength PRs") {
                    if prSnapshots.isEmpty {
                        ContentUnavailableView(
                            "No PRs yet",
                            systemImage: "trophy",
                            description: Text("Estimated 1RM records appear after weighted working sets.")
                        )
                    } else {
                        ForEach(prSnapshots.prefix(8)) { pr in
                            PRSnapshotRow(snapshot: pr)
                        }
                    }
                }
            }
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .addEntry
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { _ in
                BodyMetricEditor()
            }
            .alert(
                "Delete this body entry?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { metric in
                Button("Delete", role: .destructive) {
                    metric.deletedAt = Date()
                    try? modelContext.save()
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { _ in
                Text("This removes the entry from body tracking.")
            }
            .alert(
                "Health import failed",
                isPresented: Binding(
                    get: { healthImportError != nil },
                    set: { if !$0 { healthImportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    healthImportError = nil
                }
            } message: {
                Text(healthImportError ?? "")
            }
        }
    }

    private func importHealthBodyMetrics() async {
        isImportingHealth = true
        defer { isImportingHealth = false }

        do {
            let snapshots = try await HealthKitService.shared.fetchRecentBodyMetrics()
            let newSnapshots = snapshots.filter { !isDuplicateHealthMetric($0) }
            for snapshot in newSnapshots {
                modelContext.insert(
                    BodyMetric(
                        loggedAt: snapshot.loggedAt,
                        bodyweightLb: snapshot.bodyweightLb,
                        bodyFatPercent: snapshot.bodyFatPercent,
                        waistIn: snapshot.waistIn,
                        notes: "Imported from Health"
                    )
                )
            }
            if !newSnapshots.isEmpty {
                try? modelContext.save()
            }
            healthImportMessage = newSnapshots.isEmpty
                ? "No new Health body metrics found."
                : "Imported \(newSnapshots.count) Health entr\(newSnapshots.count == 1 ? "y" : "ies")."
        } catch {
            healthImportError = error.localizedDescription
        }
    }

    private func isDuplicateHealthMetric(_ snapshot: HealthBodyMetricSnapshot) -> Bool {
        bodyMetrics.contains { metric in
            abs(metric.loggedAt.timeIntervalSince(snapshot.loggedAt)) < 60
                && approximatelyEqual(metric.bodyweightLb, snapshot.bodyweightLb)
                && approximatelyEqual(metric.bodyFatPercent, snapshot.bodyFatPercent)
                && approximatelyEqual(metric.waistIn, snapshot.waistIn)
        }
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < 0.05
        default:
            return false
        }
    }

    private func estimatedOneRepMax(_ set: SetEntry) -> Double {
        guard let weight = set.weightLb else { return 0 }
        return weight * (1 + Double(set.reps) / 30)
    }
}

private struct BodyweightSample: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double
    let source: String
}

private struct PRSnapshot: Identifiable {
    let id: UUID
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let achievedAt: Date
}

private struct BodySummaryView: View {
    let latestBodyweight: BodyweightSample?
    let previousBodyweight: BodyweightSample?
    let latestMetric: BodyMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(latestBodyweight.map { "\(formatNumber($0.weight)) lb" } ?? "--")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(latestBodyweight.map { relativeDate($0.date) } ?? "No entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let latestBodyweight {
                        Text(latestBodyweight.source)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }

            HStack(spacing: 12) {
                SummaryPill(
                    title: "Change",
                    value: changeText,
                    systemImage: changeIcon
                )
                SummaryPill(
                    title: "Body Fat",
                    value: latestMetric?.bodyFatPercent.map { "\(formatNumber($0))%" } ?? "--",
                    systemImage: "percent"
                )
                SummaryPill(
                    title: "Waist",
                    value: latestMetric?.waistIn.map { "\(formatNumber($0)) in" } ?? "--",
                    systemImage: "ruler"
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var changeText: String {
        guard let latest = latestBodyweight, let previous = previousBodyweight else { return "--" }
        let delta = latest.weight - previous.weight
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(formatNumber(delta)) lb"
    }

    private var changeIcon: String {
        guard let latest = latestBodyweight, let previous = previousBodyweight else {
            return "minus"
        }
        if latest.weight > previous.weight { return "arrow.up.right" }
        if latest.weight < previous.weight { return "arrow.down.right" }
        return "minus"
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BodyweightTrendView: View {
    let samples: [BodyweightSample]

    var body: some View {
        GeometryReader { proxy in
            let values = samples.map(\.weight)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let range = max(maxValue - minValue, 1)
            let width = proxy.size.width
            let height = proxy.size.height
            let step = samples.count > 1 ? width / CGFloat(samples.count - 1) : 0

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * step
                        let normalized = (sample.weight - minValue) / range
                        let y = height - CGFloat(normalized) * (height - 18) - 9
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                HStack {
                    Text("\(formatNumber(minValue))")
                    Spacer()
                    Text("\(formatNumber(maxValue))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bodyweight trend")
    }
}

private struct MeasurementGrid: View {
    let metric: BodyMetric

    private var items: [MeasurementItem] {
        [
            MeasurementItem(label: "Waist", value: metric.waistIn),
            MeasurementItem(label: "Chest", value: metric.chestIn),
            MeasurementItem(label: "Hips", value: metric.hipsIn),
            MeasurementItem(label: "Left Biceps", value: metric.leftArmIn),
            MeasurementItem(label: "Right Biceps", value: metric.rightArmIn),
            MeasurementItem(label: "Left Forearm", value: metric.leftForearmIn),
            MeasurementItem(label: "Right Forearm", value: metric.rightForearmIn),
            MeasurementItem(label: "Left Thigh", value: metric.leftThighIn),
            MeasurementItem(label: "Right Thigh", value: metric.rightThighIn),
            MeasurementItem(label: "Left Calf", value: metric.leftCalfIn),
            MeasurementItem(label: "Right Calf", value: metric.rightCalfIn),
        ].filter { $0.value != nil }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 12)], spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value.map { "\(formatNumber($0)) in" } ?? "--")
                        .font(.headline)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MeasurementItem: Identifiable {
    let id = UUID()
    let label: String
    let value: Double?
}

private struct BodyMetricRow: View {
    let metric: BodyMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(shortDate(metric.loggedAt))
                    .font(.headline)
                Spacer()
                if let weight = metric.bodyweightLb {
                    Text("\(formatNumber(weight)) lb")
                        .font(.headline.monospacedDigit())
                }
            }

            HStack(spacing: 10) {
                if let bodyFat = metric.bodyFatPercent {
                    Label("\(formatNumber(bodyFat))%", systemImage: "percent")
                }
                if let waist = metric.waistIn {
                    Label("\(formatNumber(waist)) in waist", systemImage: "ruler")
                }
                if metric.hasMeasurements {
                    Label("Measurements", systemImage: "figure.stand")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let notes = metric.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PRSnapshotRow: View {
    let snapshot: PRSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.exerciseName)
                    .font(.body)
                Text("\(formatNumber(snapshot.weight)) lb x \(snapshot.reps) - \(shortDate(snapshot.achievedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(formatNumber(snapshot.estimatedOneRepMax))")
                .font(.headline.monospacedDigit())
            Text("e1RM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct BodyMetricEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthKitPreferenceKeys.writeBodyMetrics) private var writeHealthBodyMetrics = false

    @State private var loggedAt = Date()
    @State private var bodyweight = ""
    @State private var bodyFat = ""
    @State private var waist = ""
    @State private var chest = ""
    @State private var hips = ""
    @State private var leftBiceps = ""
    @State private var rightBiceps = ""
    @State private var leftForearm = ""
    @State private var rightForearm = ""
    @State private var leftThigh = ""
    @State private var rightThigh = ""
    @State private var leftCalf = ""
    @State private var rightCalf = ""
    @State private var notes = ""

    private var canSave: Bool {
        [
            bodyweight, bodyFat, waist, chest, hips,
            leftBiceps, rightBiceps, leftForearm, rightForearm,
            leftThigh, rightThigh, leftCalf, rightCalf, notes,
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $loggedAt, displayedComponents: [.date])
                    BodyNumberField(title: "Bodyweight", suffix: "lb", text: $bodyweight)
                    BodyNumberField(title: "Body Fat", suffix: "%", text: $bodyFat)
                }

                Section("Measurements") {
                    BodyNumberField(title: "Waist", suffix: "in", text: $waist)
                    BodyNumberField(title: "Chest", suffix: "in", text: $chest)
                    BodyNumberField(title: "Hips", suffix: "in", text: $hips)
                    BodyNumberField(title: "Left Biceps", suffix: "in", text: $leftBiceps)
                    BodyNumberField(title: "Right Biceps", suffix: "in", text: $rightBiceps)
                    BodyNumberField(title: "Left Forearm", suffix: "in", text: $leftForearm)
                    BodyNumberField(title: "Right Forearm", suffix: "in", text: $rightForearm)
                    BodyNumberField(title: "Left Thigh", suffix: "in", text: $leftThigh)
                    BodyNumberField(title: "Right Thigh", suffix: "in", text: $rightThigh)
                    BodyNumberField(title: "Left Calf", suffix: "in", text: $leftCalf)
                    BodyNumberField(title: "Right Calf", suffix: "in", text: $rightCalf)
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Body Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let metric = BodyMetric(
            loggedAt: loggedAt,
            bodyweightLb: doubleValue(bodyweight),
            bodyFatPercent: doubleValue(bodyFat),
            waistIn: doubleValue(waist),
            chestIn: doubleValue(chest),
            hipsIn: doubleValue(hips),
            leftArmIn: doubleValue(leftBiceps),
            rightArmIn: doubleValue(rightBiceps),
            leftForearmIn: doubleValue(leftForearm),
            rightForearmIn: doubleValue(rightForearm),
            leftThighIn: doubleValue(leftThigh),
            rightThighIn: doubleValue(rightThigh),
            leftCalfIn: doubleValue(leftCalf),
            rightCalfIn: doubleValue(rightCalf),
            notes: trimmedNotes
        )
        modelContext.insert(metric)
        try? modelContext.save()

        if writeHealthBodyMetrics {
            let snapshot = HealthBodyMetricSnapshot(metric: metric)
            Task {
                try? await HealthKitService.shared.saveBodyMetric(snapshot)
            }
        }
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }
}

private struct BodyNumberField: View {
    let title: String
    let suffix: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Optional", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
    }
}

private extension BodyMetric {
    var hasMeasurements: Bool {
        waistIn != nil
            || chestIn != nil
            || hipsIn != nil
            || leftArmIn != nil
            || rightArmIn != nil
            || leftForearmIn != nil
            || rightForearmIn != nil
            || leftThighIn != nil
            || rightThighIn != nil
            || leftCalfIn != nil
            || rightCalfIn != nil
    }
}

private func formatNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

#Preview {
    BodyView()
        .modelContainer(for: IronSchemaV1.models, inMemory: true)
}
