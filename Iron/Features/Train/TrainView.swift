import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Workout> { $0.finishedAt == nil && $0.deletedAt == nil })
    private var activeWorkouts: [Workout]
    @Query(filter: #Predicate<Program> { $0.deletedAt == nil }, sort: \Program.name)
    private var programs: [Program]

    @State private var path = NavigationPath()

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
            .navigationDestination(for: ProgramDay.self) { day in
                ProgramDayDetailView(day: day) { workout in
                    path = NavigationPath()
                    modelContext.insert(workout)
                    try? modelContext.save()
                }
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
                        ProgramRow(program: program)
                    }
                }
            }
        }
    }
}

private struct ProgramRow: View {
    let program: Program

    var body: some View {
        DisclosureGroup {
            ForEach(program.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                NavigationLink(value: day) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name)
                            .font(.body)
                        Text(exerciseSummary(day))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name)
                    .font(.headline)
                if let author = program.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exerciseSummary(_ day: ProgramDay) -> String {
        day.exercises
            .sorted(by: { $0.orderIndex < $1.orderIndex })
            .compactMap { $0.exercise?.name }
            .joined(separator: " · ")
    }
}

#Preview {
    TrainView()
        .modelContainer(for: IronSchemaV1.models, inMemory: true)
}
