import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let program: Program

    @Query(
        filter: #Predicate<Workout> { $0.finishedAt != nil && $0.deletedAt == nil },
        sort: \Workout.finishedAt
    )
    private var completedWorkouts: [Workout]

    @State private var showFullDescription = false
    @State private var workoutWeekdays: [Int] = []
    @State private var editorPresentation: ProgramEditorPresentation?
    @State private var isShowingDeleteConfirmation = false

    private enum ProgramEditorPresentation: Identifiable {
        case edit
        case duplicate

        var id: String {
            switch self {
            case .edit: "edit"
            case .duplicate: "duplicate"
            }
        }

        var mode: ProgramEditorMode {
            switch self {
            case .edit: .edit
            case .duplicate: .duplicate
            }
        }
    }

    private struct WeekGroup: Identifiable {
        let id: String
        let label: String
        let days: [ProgramDay]
    }

    private struct RestMarker: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    private struct ScheduleRow: Identifiable {
        enum Kind {
            case workout(ProgramDay)
            case rest(RestMarker)
        }

        let id: String
        let kind: Kind
    }

    private struct WeekdayOption: Identifiable {
        let id: Int
        let name: String
        let shortName: String
    }

    private struct WeeklyScheduleRow: Identifiable {
        enum Kind {
            case workout(ProgramDay)
            case rest(String)
        }

        let id: Int
        let weekday: WeekdayOption
        let kind: Kind
    }

    private var completedDayIDs: Set<UUID> {
        Set(
            completedWorkouts.compactMap { workout in
                guard workout.sourceProgramDay?.program?.id == program.id else { return nil }
                return workout.sourceProgramDay?.id
            }
        )
    }

    private var orderedDays: [ProgramDay] {
        program.days.sorted(by: daySort)
    }

    private var nextWorkoutDay: ProgramDay? {
        orderedDays.first { !completedDayIDs.contains($0.id) }
    }

    private var weekGroups: [WeekGroup] {
        let active = orderedDays
        guard !active.isEmpty else { return [] }

        if active.contains(where: { $0.weekIndex != nil || $0.phaseIndex != nil }) {
            let grouped = Dictionary(grouping: active) { day in
                WeekKey(phaseIndex: day.phaseIndex, phaseName: day.phaseName, weekIndex: day.weekIndex)
            }

            return grouped.keys.sorted().map { key in
                WeekGroup(
                    id: key.id,
                    label: key.label,
                    days: (grouped[key] ?? []).sorted(by: daySort)
                )
            }
        }

        return [WeekGroup(id: "workouts", label: "Workouts", days: active.sorted(by: daySort))]
    }

    var body: some View {
        List {
            Section { headerCard }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

            if let desc = program.programDescription, !desc.isEmpty {
                Section("About") {
                    Text(desc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(showFullDescription ? nil : 4)
                    Button(showFullDescription ? "Show less" : "Read more") {
                        withAnimation { showFullDescription.toggle() }
                    }
                    .font(.footnote)
                }
            }

            if let nextWorkoutDay {
                Section("Up Next") {
                    NavigationLink(value: nextWorkoutDay) {
                        DayRow(
                            day: nextWorkoutDay,
                            dayNumber: nextWorkoutDay.dayIndex + 1,
                            isCompleted: false
                        )
                    }
                }
            }

            if usesWeeklySchedule {
                Section("Workout Days") {
                    ForEach(Array(orderedDays.enumerated()), id: \.element.id) { index, day in
                        Picker(workoutPickerTitle(for: day, index: index), selection: weekdayBinding(for: index)) {
                            ForEach(weekdayOptions) { option in
                                Text(option.name)
                                    .tag(option.id)
                                    .disabled(isWeekdayUnavailable(option.id, forWorkoutAt: index))
                            }
                        }
                    }
                }

                Section("Week") {
                    ForEach(weeklyScheduleRows) { row in
                        switch row.kind {
                        case .workout(let day):
                            NavigationLink(value: day) {
                                WeeklyWorkoutRow(
                                    weekday: row.weekday.name,
                                    day: day,
                                    isCompleted: completedDayIDs.contains(day.id)
                                )
                            }
                        case .rest(let instructions):
                            RestDayRow(
                                title: "\(row.weekday.name) - Rest Day",
                                subtitle: instructions
                            )
                        }
                    }
                }
            } else {
                ForEach(weekGroups) { group in
                    Section(group.label) {
                        ForEach(scheduleRows(for: group)) { row in
                            switch row.kind {
                            case .workout(let day):
                                NavigationLink(value: day) {
                                    DayRow(
                                        day: day,
                                        dayNumber: day.dayIndex + 1,
                                        isCompleted: completedDayIDs.contains(day.id)
                                    )
                                }
                            case .rest(let rest):
                                RestDayRow(title: rest.title, subtitle: rest.subtitle)
                            }
                        }
                    }
                }
            }

            Section("Settings") {
                LabeledContent("Author", value: program.author ?? "—")
                LabeledContent("Length", value: program.weeksLength.map { "\($0) weeks" } ?? "Open-ended")
                LabeledContent("Days per week", value: daysPerWeekText)
                if usesWeeklySchedule {
                    LabeledContent("Workout days", value: selectedWeekdaysText)
                }
                LabeledContent("Type", value: program.isBuiltIn ? "Built-in" : "Custom")
            }
            .font(.callout)
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadWorkoutWeekdaysIfNeeded)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editorPresentation = .duplicate
                    } label: {
                        Label("Duplicate Program", systemImage: "doc.on.doc")
                    }

                    if !program.isBuiltIn {
                        Button {
                            editorPresentation = .edit
                        } label: {
                            Label("Edit Program", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Program", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Program actions")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            ProgramEditorView(mode: presentation.mode, program: program)
        }
        .alert("Delete Program?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                program.deletedAt = Date()
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the program template. Completed workout history stays in History.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(program.name)
                .font(.title2.bold())
            if let author = program.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let weeks = program.weeksLength {
                    Label("\(weeks) weeks", systemImage: "calendar")
                }
                Label(scheduleText, systemImage: "calendar.day.timeline.left")
                if program.isBuiltIn {
                    Label("Built-in", systemImage: "checkmark.seal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scheduleText: String {
        if let dpw = program.daysPerWeek {
            return "\(dpw) days/week"
        }
        return "\(program.days.count) workouts"
    }

    private var daysPerWeekText: String {
        program.daysPerWeek.map { "\($0)" } ?? "—"
    }

    private var usesWeeklySchedule: Bool {
        program.daysPerWeek == 2 && orderedDays.count == 2
    }

    private var weekdayOptions: [WeekdayOption] {
        [
            WeekdayOption(id: 2, name: "Monday", shortName: "Mon"),
            WeekdayOption(id: 3, name: "Tuesday", shortName: "Tue"),
            WeekdayOption(id: 4, name: "Wednesday", shortName: "Wed"),
            WeekdayOption(id: 5, name: "Thursday", shortName: "Thu"),
            WeekdayOption(id: 6, name: "Friday", shortName: "Fri"),
            WeekdayOption(id: 7, name: "Saturday", shortName: "Sat"),
            WeekdayOption(id: 1, name: "Sunday", shortName: "Sun"),
        ]
    }

    private var defaultWorkoutWeekdays: [Int] {
        guard orderedDays.count == 2 else {
            return Array(weekdayOptions.prefix(max(0, orderedDays.count)).map(\.id))
        }
        return [2, 5]
    }

    private var selectedWorkoutWeekdays: [Int] {
        guard workoutWeekdays.count == orderedDays.count else { return defaultWorkoutWeekdays }
        return workoutWeekdays
    }

    private var selectedWeekdaysText: String {
        selectedWorkoutWeekdays
            .compactMap { weekdayOption(for: $0)?.shortName }
            .joined(separator: " / ")
    }

    private var weeklyScheduleRows: [WeeklyScheduleRow] {
        let selectedDays = selectedWorkoutWeekdays
        let workoutByWeekday = Dictionary(uniqueKeysWithValues: zip(selectedDays, orderedDays))

        return weekdayOptions.map { weekday in
            if let day = workoutByWeekday[weekday.id] {
                return WeeklyScheduleRow(id: weekday.id, weekday: weekday, kind: .workout(day))
            }
            return WeeklyScheduleRow(
                id: weekday.id,
                weekday: weekday,
                kind: .rest(restDayInstructions(for: weekday.id))
            )
        }
    }

    private var scheduleStorageKey: String {
        "programScheduleWeekdays.\(program.id.uuidString)"
    }

    private var legacyScheduleStorageKey: String {
        "programScheduleWeekdays.\(program.name)"
    }

    private func weekdayOption(for id: Int) -> WeekdayOption? {
        weekdayOptions.first { $0.id == id }
    }

    private func workoutPickerTitle(for day: ProgramDay, index: Int) -> String {
        let fallback = "Workout \(index + 1)"
        let name = day.name.isEmpty ? fallback : day.name
        return name
    }

    private func weekdayBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                selectedWorkoutWeekdays.indices.contains(index)
                    ? selectedWorkoutWeekdays[index]
                    : defaultWorkoutWeekdays[min(index, max(0, defaultWorkoutWeekdays.count - 1))]
            },
            set: { newValue in
                var updated = selectedWorkoutWeekdays
                guard updated.indices.contains(index) else { return }
                if let duplicateIndex = updated.firstIndex(of: newValue), duplicateIndex != index {
                    updated[duplicateIndex] = updated[index]
                }
                updated[index] = newValue
                workoutWeekdays = updated
                saveWorkoutWeekdays(updated)
            }
        )
    }

    private func isWeekdayUnavailable(_ weekday: Int, forWorkoutAt index: Int) -> Bool {
        selectedWorkoutWeekdays.enumerated().contains { otherIndex, selected in
            otherIndex != index && selected == weekday
        }
    }

    private func loadWorkoutWeekdaysIfNeeded() {
        guard usesWeeklySchedule else { return }
        guard workoutWeekdays.count != orderedDays.count else { return }

        let storedString = UserDefaults.standard.string(forKey: scheduleStorageKey)
            ?? UserDefaults.standard.string(forKey: legacyScheduleStorageKey)
        let stored = storedString?
            .split(separator: ",")
            .compactMap { Int($0) }
            .filter { weekdayOption(for: $0) != nil }

        if let stored, stored.count == orderedDays.count, Set(stored).count == stored.count {
            workoutWeekdays = stored
        } else {
            workoutWeekdays = defaultWorkoutWeekdays
            saveWorkoutWeekdays(defaultWorkoutWeekdays)
        }
    }

    private func saveWorkoutWeekdays(_ weekdays: [Int]) {
        UserDefaults.standard.set(
            weekdays.map(String.init).joined(separator: ","),
            forKey: scheduleStorageKey
        )
    }

    private func restDayInstructions(for weekday: Int) -> String {
        let selected = selectedWorkoutWeekdays
        guard selected.count == 2 else {
            return "No lifting today. Keep activity easy, recover, and prepare for the next session."
        }

        let first = selected[0]
        let second = selected[1]
        if dayDistance(from: first, to: weekday) == 1 || dayDistance(from: second, to: weekday) == 1 {
            return "Prioritize recovery: easy walking, mobility, hydration, and enough food to be ready for the next workout."
        }
        if dayDistance(from: weekday, to: first) == 1 || dayDistance(from: weekday, to: second) == 1 {
            return "Keep fatigue low today. Avoid hard extra lifting so tomorrow's 2-2-2 session stays high quality."
        }
        return "Rest from lifting. Light cardio, stretching, and normal daily activity are fine if they do not affect recovery."
    }

    private func dayDistance(from start: Int, to end: Int) -> Int {
        let order = weekdayOptions.map(\.id)
        guard let startIndex = order.firstIndex(of: start), let endIndex = order.firstIndex(of: end) else {
            return 0
        }
        return (endIndex - startIndex + order.count) % order.count
    }

    private func scheduleRows(for group: WeekGroup) -> [ScheduleRow] {
        let sortedDays = group.days.sorted(by: daySort)
        var rows: [ScheduleRow] = []
        for day in sortedDays {
            rows.append(ScheduleRow(id: "workout-\(day.id)", kind: .workout(day)))

            if isBodybuildingBeginnerProgram {
                if day.dayIndex == 1 {
                    rows.append(
                        ScheduleRow(
                            id: "rest-\(day.id)-lower",
                            kind: .rest(
                                RestMarker(
                                    id: "rest-\(day.id)-lower",
                                    title: "Rest Day",
                                    subtitle: "After Day 2 - Lower Strength"
                                )
                            )
                        )
                    )
                } else if day.dayIndex == 4 {
                    rows.append(
                        ScheduleRow(
                            id: "rest-\(day.id)-legs",
                            kind: .rest(
                                RestMarker(
                                    id: "rest-\(day.id)-legs",
                                    title: "Rest Day",
                                    subtitle: "After Day 5 - Legs Hypertrophy"
                                )
                            )
                        )
                    )
                }
            }
        }
        return rows
    }

    private var isBodybuildingBeginnerProgram: Bool {
        program.name == "Bodybuilding Transformation System — Beginner"
    }

    private func daySort(_ lhs: ProgramDay, _ rhs: ProgramDay) -> Bool {
        let lhsPhase = lhs.phaseIndex ?? 0
        let rhsPhase = rhs.phaseIndex ?? 0
        if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }

        let lhsWeek = lhs.weekIndex ?? 0
        let rhsWeek = rhs.weekIndex ?? 0
        if lhsWeek != rhsWeek { return lhsWeek < rhsWeek }

        return lhs.dayIndex < rhs.dayIndex
    }

    private struct WeekKey: Hashable, Comparable {
        let phaseIndex: Int?
        let phaseName: String?
        let weekIndex: Int?

        var id: String {
            "\(phaseIndex ?? 0)-\(weekIndex ?? 0)"
        }

        var label: String {
            var parts: [String] = []
            if let phaseIndex {
                if let phaseName, !phaseName.isEmpty {
                    parts.append("Phase \(phaseIndex) - \(phaseName)")
                } else {
                    parts.append("Phase \(phaseIndex)")
                }
            }
            if let weekIndex {
                parts.append("Week \(weekIndex)")
            }
            return parts.isEmpty ? "Workouts" : parts.joined(separator: " - ")
        }

        static func < (lhs: WeekKey, rhs: WeekKey) -> Bool {
            let lhsPhase = lhs.phaseIndex ?? 0
            let rhsPhase = rhs.phaseIndex ?? 0
            if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }
            return (lhs.weekIndex ?? 0) < (rhs.weekIndex ?? 0)
        }
    }
}

private struct DayRow: View {
    let day: ProgramDay
    let dayNumber: Int?
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(exerciseSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if let dayNumber {
            if workoutName == "Day \(dayNumber)" {
                return workoutName
            }
            return "Day \(dayNumber) - \(workoutName)"
        }
        return workoutName
    }

    private var workoutName: String {
        guard let separator = day.name.range(of: "—") else {
            return day.name
        }
        return day.name[separator.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var exerciseSummary: String {
        let names = day.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.exercise?.name }
        return names.isEmpty ? "—" : names.joined(separator: " · ")
    }
}

private struct WeeklyWorkoutRow: View {
    let weekday: String
    let day: ProgramDay
    let isCompleted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "dumbbell")
                .foregroundStyle(isCompleted ? Color.green : Color.accentColor)
                .font(.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(weekday) - \(day.name)")
                    .font(.body)
                Text(exerciseSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var exerciseSummary: String {
        let names = day.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.exercise?.name }
        return names.isEmpty ? "—" : names.joined(separator: " · ")
    }
}

private struct RestDayRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
                .font(.body)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
