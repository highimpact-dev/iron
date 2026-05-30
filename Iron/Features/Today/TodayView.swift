import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthKitPreferenceKeys.readDailyHealth) private var readDailyHealth = false

    @Query(sort: \DailyHealthSnapshot.dayStart, order: .reverse) private var snapshots: [DailyHealthSnapshot]

    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var refreshError: String?
    @State private var selectedScore: TodayScoreKind?

    private var currentSnapshot: DailyHealthSnapshot? {
        let today = Calendar.current.startOfDay(for: Date())
        return snapshots.first { Calendar.current.isDate($0.dayStart, inSameDayAs: today) } ?? snapshots.first
    }

    private var analysis: TodayDashboardAnalysis {
        TodayDashboardAnalysis(snapshot: currentSnapshot, history: snapshots)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                morningSummarySection
                trainingReadinessSection

                Section {
                    scoreGrid
                } footer: {
                    Text("Iron scores are transparent HealthKit heuristics, not Bevel's proprietary algorithm. Baseline-based recovery needs at least 14 prior days of HRV and resting heart-rate data.")
                }

                trendsSection
                vitalsAlertsSection
                weeklyLoadSection

                Section("Health Monitor") {
                    if let snapshot = currentSnapshot {
                        metricRow("HRV", value: format(snapshot.hrvMs, suffix: " ms"), trend: hrvTrend(snapshot), systemImage: "waveform.path.ecg")
                        metricRow("Resting heart rate", value: format(snapshot.restingHeartRate, suffix: " bpm"), trend: rhrTrend(snapshot), systemImage: "heart")
                        metricRow("Respiratory rate", value: format(snapshot.respiratoryRate, suffix: " /min"), trend: nil, systemImage: "lungs")
                        metricRow("Blood oxygen", value: format(snapshot.oxygenSaturationPercent, suffix: "%"), trend: oxygenTrend(snapshot), systemImage: "drop")
                        metricRow("Wrist temperature", value: format(snapshot.wristTemperatureCelsius, suffix: " C"), trend: temperatureTrend(snapshot), systemImage: "thermometer")
                        metricRow("VO2 max", value: format(snapshot.vo2Max, suffix: " ml/kg/min"), trend: vo2MaxTrend(snapshot), systemImage: "gauge.with.dots.needle.67percent")
                    } else {
                        ContentUnavailableView("No health snapshot yet", systemImage: "heart.text.square", description: Text("Refresh after enabling Daily Health access in Settings."))
                    }
                }

                Section("Activity Summary") {
                    if let snapshot = currentSnapshot {
                        metricRow("Steps", value: format(snapshot.steps, maximumFractionDigits: 0), trend: nil, systemImage: "figure.walk")
                        metricRow("Exercise", value: format(snapshot.exerciseMinutes, suffix: " min", maximumFractionDigits: 0), trend: nil, systemImage: "figure.run")
                        metricRow("Active energy", value: format(snapshot.activeEnergyKcal, suffix: " kcal", maximumFractionDigits: 0), trend: nil, systemImage: "flame")
                        metricRow("Resting energy", value: format(snapshot.restingEnergyKcal, suffix: " kcal", maximumFractionDigits: 0), trend: nil, systemImage: "bolt.heart")
                        metricRow("Workouts", value: "\(snapshot.workoutCount)", trend: nil, systemImage: "dumbbell")
                    }
                }

                Section("Recent Sleep") {
                    if let snapshot = currentSnapshot {
                        metricRow("Sleep duration", value: duration(snapshot.sleepDurationMinutes), trend: sleepTrend(snapshot), systemImage: "bed.double")
                        metricRow("Time in bed", value: duration(snapshot.timeInBedMinutes), trend: nil, systemImage: "moon")
                        metricRow("Efficiency", value: percent(snapshot.sleepEfficiency), trend: nil, systemImage: "chart.line.uptrend.xyaxis")
                        metricRow("Sleep window", value: sleepWindow(snapshot), trend: nil, systemImage: "clock")
                        metricRow("Sleep debt", value: "\(Int(analysis.sleepDebtHours.rounded())) hr", trend: "Last 7 days vs 8h goal", systemImage: "moon.zzz")
                    }
                }

                diagnosticsSection
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshDailyHealth() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || !HealthKitService.isAvailable || !readDailyHealth)
                }
            }
            .refreshable {
                await refreshDailyHealth()
            }
            .alert(
                "Health refresh failed",
                isPresented: Binding(
                    get: { refreshError != nil },
                    set: { if !$0 { refreshError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    refreshError = nil
                }
            } message: {
                Text(refreshError ?? "")
            }
            .sheet(item: $selectedScore) { kind in
                ScoreDetailView(breakdown: analysis.scoreBreakdown(for: kind), systemImage: kind.systemImage)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.headline)
                if !HealthKitService.isAvailable {
                    Label("Health data is not available on this device.", systemImage: "heart.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !readDailyHealth {
                    Label("Turn on Daily Health in Settings to import Apple Health and Watch data.", systemImage: "heart.text.square")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let refreshMessage {
                    Label(refreshMessage, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Pull to refresh or use the toolbar button for today's HealthKit import.", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var morningSummarySection: some View {
        Section {
            Label(analysis.morningSummary, systemImage: "sun.max")
                .foregroundStyle(.primary)
        }
    }

    private var trainingReadinessSection: some View {
        Section("Training Readiness") {
            VStack(alignment: .leading, spacing: 10) {
                Label(analysis.readiness.title, systemImage: analysis.readiness.systemImage)
                    .font(.headline)
                Text(analysis.readiness.action)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(analysis.readiness.details, id: \.self) { detail in
                    Label(detail, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var scoreGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button {
                selectedScore = .recovery
            } label: {
                ScoreCard(title: "Recovery", score: currentSnapshot?.recoveryScore, systemImage: TodayScoreKind.recovery.systemImage)
            }
            .buttonStyle(.plain)

            Button {
                selectedScore = .sleep
            } label: {
                ScoreCard(title: "Sleep", score: currentSnapshot?.sleepScore, systemImage: TodayScoreKind.sleep.systemImage)
            }
            .buttonStyle(.plain)

            Button {
                selectedScore = .strain
            } label: {
                ScoreCard(title: "Strain", score: currentSnapshot?.strainScore, systemImage: TodayScoreKind.strain.systemImage)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private var trendsSection: some View {
        Section("Trends") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(analysis.trendCards) { card in
                        TrendCard(card: card)
                            .frame(width: 150)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
        }
    }

    private var vitalsAlertsSection: some View {
        Section("Insights") {
            if analysis.vitalsAlerts.isEmpty {
                Label("No major vitals alerts from today's Health data.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(analysis.vitalsAlerts) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(alert.title, systemImage: alert.systemImage)
                            .font(.headline)
                        Text(alert.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var weeklyLoadSection: some View {
        Section {
            WeeklyLoadChart(points: analysis.weeklyLoad)
                .frame(height: 130)
                .padding(.vertical, 6)
        } header: {
            Text("Weekly Load")
        } footer: {
            Text("Load blends active energy, exercise minutes, workouts, and steps so you can see ramp-up across the week.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Data Sources") {
            ForEach(analysis.diagnostics) { diagnostic in
                HStack(spacing: 12) {
                    Image(systemName: diagnostic.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.title)
                        Text(diagnostic.date.map { "Latest: \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No recent Health sample")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(diagnostic.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(diagnostic.status == "Available" ? .green : .secondary)
                }
            }
        }
    }

    private func refreshDailyHealth() async {
        guard !isRefreshing else { return }
        guard HealthKitService.isAvailable else {
            refreshError = "Health data is not available on this device."
            return
        }
        guard readDailyHealth else {
            refreshError = "Turn on Daily Health in Settings first."
            return
        }

        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }

        do {
            let count = try await DailyHealthService.refreshRecentSnapshots(context: modelContext, days: 31)
            refreshMessage = count > 0 ? "Updated \(count) daily snapshots." : "No HealthKit data was available to import."
        } catch {
            refreshError = error.localizedDescription
        }
    }

    private func metricRow(_ title: String, value: String, trend: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let trend {
                    Text(trend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private func format(
        _ value: Double?,
        suffix: String = "",
        maximumFractionDigits: Int = 1
    ) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = maximumFractionDigits == 0 ? 0 : 1
        return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)")\(suffix)"
    }

    private func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "--" }
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        return "\(hours)h \(mins)m"
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func sleepWindow(_ snapshot: DailyHealthSnapshot) -> String {
        guard let start = snapshot.sleepStart, let end = snapshot.sleepEnd else { return "--" }
        return "\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func hrvTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard let value = snapshot.hrvMs, let baseline = snapshot.hrvBaselineMs, baseline > 0 else { return nil }
        if value >= baseline * 1.08 { return "Above baseline" }
        if value <= baseline * 0.92 { return "Below baseline" }
        return "Near baseline"
    }

    private func rhrTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard let value = snapshot.restingHeartRate, let baseline = snapshot.restingHeartRateBaseline, baseline > 0 else { return nil }
        if value <= baseline * 0.95 { return "Below baseline" }
        if value >= baseline * 1.05 { return "Above baseline" }
        return "Near baseline"
    }

    private func oxygenTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard let value = snapshot.oxygenSaturationPercent else { return nil }
        return value >= 95 ? "Normal range" : "Below usual range"
    }

    private func temperatureTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard let value = snapshot.wristTemperatureCelsius else { return nil }
        return value > 0 ? "Latest sleep sample" : nil
    }

    private func vo2MaxTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard snapshot.vo2Max != nil else { return nil }
        return "Latest Health estimate"
    }

    private func sleepTrend(_ snapshot: DailyHealthSnapshot) -> String? {
        guard let score = snapshot.sleepScore else { return nil }
        if score >= 75 { return "Strong sleep" }
        if score >= 55 { return "Adequate sleep" }
        return "Poor sleep"
    }

    private func readinessIcon(_ snapshot: DailyHealthSnapshot) -> String {
        guard let recovery = snapshot.recoveryScore else { return "questionmark.circle" }
        return recovery >= 75 ? "checkmark.circle" : recovery >= 55 ? "exclamationmark.circle" : "pause.circle"
    }
}

private struct ScoreCard: View {
    let title: String
    let score: Int?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(scoreText)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(scoreColor)
            Text(stateText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scoreColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(scoreColor.opacity(0.25))
        )
    }

    private var scoreText: String {
        score.map(String.init) ?? "--"
    }

    private var stateText: String {
        guard let score else { return "Insufficient data" }
        if score >= 75 { return "High" }
        if score >= 55 { return "Normal" }
        return "Low"
    }

    private var scoreColor: Color {
        guard let score else { return .secondary }
        if score >= 75 { return .green }
        if score >= 55 { return .orange }
        return .red
    }
}

private struct TrendCard: View {
    let card: TrendCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(card.title, systemImage: card.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            Text(valueText)
                .font(.title2.weight(.bold).monospacedDigit())
            SparklineBars(values: card.values)
                .frame(height: 34)
            Text(deltaText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(deltaColor)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var valueText: String {
        if card.unit.isEmpty {
            return "\(Int(card.current.rounded()))"
        }
        return "\(Int(card.current.rounded())) \(card.unit)"
    }

    private var deltaText: String {
        guard let delta = card.delta else { return "Needs history" }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Int(delta.rounded())) vs 7d"
    }

    private var deltaColor: Color {
        guard let delta = card.delta else { return .secondary }
        return delta >= 0 ? .green : .orange
    }
}

private struct SparklineBars: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(height: max(4, proxy.size.height * value / maxValue))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

private struct WeeklyLoadChart: View {
    let points: [DailyLoadPoint]

    var body: some View {
        GeometryReader { proxy in
            let maxLoad = max(points.map(\.load).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(points) { point in
                    VStack(spacing: 6) {
                        Text(point.score.map(String.init) ?? "--")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(loadColor(point.score).gradient)
                            .frame(height: max(8, (proxy.size.height - 34) * point.load / maxLoad))
                        Text(point.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func loadColor(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        if score >= 75 { return .red }
        if score >= 55 { return .orange }
        return .green
    }
}

private struct ScoreDetailView: View {
    let breakdown: ScoreBreakdown
    let systemImage: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: systemImage)
                            .font(.largeTitle)
                            .foregroundStyle(scoreColor)
                            .frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(breakdown.score.map(String.init) ?? "--")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .monospacedDigit()
                            Text(scoreState)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Breakdown") {
                    ForEach(breakdown.components) { component in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(component.title)
                                Spacer()
                                Text("\(Int(component.value.rounded()))")
                                    .font(.headline.monospacedDigit())
                            }
                            ProgressView(value: min(max(component.value, 0), 100), total: 100)
                            Text("\(Int((component.weight * 100).rounded()))% weight - \(component.detail)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Notes") {
                    ForEach(breakdown.notes, id: \.self) { note in
                        Text(note)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(breakdown.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var scoreState: String {
        guard let score = breakdown.score else { return "Insufficient data" }
        if score >= 75 { return "High" }
        if score >= 55 { return "Normal" }
        return "Low"
    }

    private var scoreColor: Color {
        guard let score = breakdown.score else { return .secondary }
        if score >= 75 { return .green }
        if score >= 55 { return .orange }
        return .red
    }
}

#Preview("No Data") {
    TodayView()
        .modelContainer(for: IronSchemaV3.models, inMemory: true)
}

#Preview("Partial") {
    TodayView()
        .modelContainer(TodayPreviewContainer.partial)
}

#Preview("Complete") {
    TodayView()
        .modelContainer(TodayPreviewContainer.complete)
}

@MainActor
private enum TodayPreviewContainer {
    static var partial: ModelContainer {
        let container = try! ModelContainer(for: Schema(IronSchemaV3.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let snapshot = DailyHealthSnapshot(dayStart: Calendar.current.startOfDay(for: Date()))
        snapshot.sleepScore = 62
        snapshot.sleepDurationMinutes = 365
        snapshot.timeInBedMinutes = 430
        snapshot.sleepEfficiency = 0.85
        snapshot.steps = 4200
        snapshot.activeEnergyKcal = 280
        snapshot.exerciseMinutes = 18
        snapshot.workoutCount = 0
        snapshot.trainingReadiness = DailyHealthCalculator.readinessText(recoveryScore: snapshot.recoveryScore, strainScore: snapshot.strainScore)
        container.mainContext.insert(snapshot)
        return container
    }

    static var complete: ModelContainer {
        let container = try! ModelContainer(for: Schema(IronSchemaV3.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let snapshot = DailyHealthSnapshot(dayStart: Calendar.current.startOfDay(for: Date()))
        snapshot.recoveryScore = 82
        snapshot.sleepScore = 78
        snapshot.strainScore = 64
        snapshot.hrvMs = 45
        snapshot.hrvBaselineMs = 42
        snapshot.restingHeartRate = 58
        snapshot.restingHeartRateBaseline = 60
        snapshot.respiratoryRate = 14
        snapshot.oxygenSaturationPercent = 97
        snapshot.wristTemperatureCelsius = 0.2
        snapshot.vo2Max = 42
        snapshot.steps = 8200
        snapshot.activeEnergyKcal = 520
        snapshot.restingEnergyKcal = 1680
        snapshot.exerciseMinutes = 48
        snapshot.workoutCount = 1
        snapshot.sleepDurationMinutes = 455
        snapshot.timeInBedMinutes = 500
        snapshot.sleepEfficiency = 0.91
        snapshot.sleepStart = Calendar.current.date(byAdding: .hour, value: -9, to: Date())
        snapshot.sleepEnd = Calendar.current.date(byAdding: .hour, value: -1, to: Date())
        snapshot.trainingReadiness = DailyHealthCalculator.readinessText(recoveryScore: snapshot.recoveryScore, strainScore: snapshot.strainScore)
        container.mainContext.insert(snapshot)
        return container
    }
}
