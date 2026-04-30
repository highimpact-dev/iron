import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(
        filter: #Predicate<Workout> { $0.finishedAt != nil && $0.deletedAt == nil },
        sort: \Workout.finishedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "calendar",
                        description: Text("Logged sessions will appear here.")
                    )
                } else {
                    List {
                        ForEach(groupedWorkouts, id: \.key) { group in
                            Section(group.key) {
                                ForEach(group.value) { workout in
                                    NavigationLink(value: workout) {
                                        WorkoutRow(workout: workout)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutDetailView(workout: workout)
            }
        }
    }

    private var groupedWorkouts: [(key: String, value: [Workout])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let groups = Dictionary(grouping: workouts) { workout in
            formatter.string(from: workout.finishedAt ?? workout.startedAt)
        }
        return groups.sorted { lhs, rhs in
            let lDate = lhs.value.first?.finishedAt ?? lhs.value.first?.startedAt ?? .distantPast
            let rDate = rhs.value.first?.finishedAt ?? rhs.value.first?.startedAt ?? .distantPast
            return lDate > rDate
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    private var dateText: String {
        let date = workout.finishedAt ?? workout.startedAt
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var titleText: String {
        if let name = workout.name, !name.isEmpty { return name }
        if let prog = workout.sourceProgram?.name { return prog }
        return "Workout"
    }

    private var durationText: String {
        guard let finished = workout.finishedAt else { return "—" }
        let total = Int(finished.timeIntervalSince(workout.startedAt))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var setCount: Int { workout.setEntries.count }

    private var totalVolume: Double {
        workout.setEntries.reduce(0.0) { acc, set in
            acc + Double(set.reps) * (set.weightLb ?? 0)
        }
    }

    private var volumeText: String {
        guard totalVolume > 0 else { return "BW" }
        return "\(Int(totalVolume.rounded())) lb"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(titleText)
                    .font(.headline)
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label(durationText, systemImage: "clock")
                Label("\(setCount) sets", systemImage: "list.bullet")
                Label(volumeText, systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: IronSchemaV1.models, inMemory: true)
}
