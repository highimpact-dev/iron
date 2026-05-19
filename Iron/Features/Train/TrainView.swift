import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Workout> { $0.finishedAt == nil && $0.deletedAt == nil })
    private var activeWorkouts: [Workout]
    @Query(filter: #Predicate<Program> { $0.deletedAt == nil }, sort: \Program.name)
    private var programs: [Program]

    @State private var path = NavigationPath()
    @State private var isCreatingProgram = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let active = activeWorkouts.first {
                    ActiveWorkoutView(workout: active)
                } else {
                    programList
                }
            }
            .navigationTitle("Train")
            .navigationDestination(for: Program.self) { program in
                ProgramDetailView(program: program)
            }
            .navigationDestination(for: ProgramDay.self) { day in
                ProgramDayDetailView(day: day) { workout in
                    path = NavigationPath()
                    modelContext.insert(workout)
                    try? modelContext.save()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreatingProgram = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create program")
                }
            }
            .sheet(isPresented: $isCreatingProgram) {
                ProgramEditorView(mode: .create)
            }
        }
    }

    private var programList: some View {
        List {
            if programs.isEmpty {
                ContentUnavailableView(
                    "No programs yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Programs will appear after first launch.")
                )
            } else {
                Section("Programs") {
                    ForEach(programs) { program in
                        NavigationLink(value: program) {
                            ProgramRow(program: program)
                        }
                    }
                }
            }
        }
    }
}

private struct ProgramRow: View {
    let program: Program

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name)
                .font(.headline)
            if let author = program.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let weeks = program.weeksLength {
                    Label("\(weeks) wk", systemImage: "calendar")
                }
                if let dpw = program.daysPerWeek {
                    Label("\(dpw) days/week", systemImage: "calendar.day.timeline.left")
                } else {
                    Label("\(program.days.count) workouts", systemImage: "list.bullet.rectangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TrainView()
        .modelContainer(for: IronSchemaV2.models, inMemory: true)
}
