import Foundation

enum ExerciseCategory: String, Codable, CaseIterable {
    case compound, isolation, conditioning
}

enum MovementPattern: String, Codable, CaseIterable {
    case squat, hinge, push, pull, carry, core, conditioning
}

enum Muscle: String, Codable, CaseIterable {
    case quads, glutes, hamstrings, calves
    case chest, lats, traps, rearDelts, sideDelts, frontDelts
    case biceps, triceps, forearms
    case core, lowerBack
    case fullBody
}

enum Equipment: String, Codable, CaseIterable {
    case barbell, dumbbell, kettlebell, machine, cable
    case bodyweight, band, rack, bench, box
    case treadmill, rower, bike, assault, ski
}

enum SetType: String, Codable, CaseIterable {
    case working, warmup, dropSet, amrap, restPause, failure

    var label: String {
        switch self {
        case .working: return "Working"
        case .warmup: return "Warm-up"
        case .dropSet: return "Drop set"
        case .amrap: return "AMRAP"
        case .restPause: return "Rest-pause"
        case .failure: return "Failure"
        }
    }
}

enum SetSide: String, Codable, CaseIterable {
    case left, right

    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

enum ConditioningModality: String, Codable, CaseIterable {
    case run, row, bike, hiit, interval, ruck, swim, ski, custom
}

enum PRType: String, Codable, CaseIterable {
    case oneRM, threeRM, fiveRM, e1RM, volume, amrapReps
}

enum WeightUnit: String, Codable, CaseIterable { case lb, kg }
enum DistanceUnit: String, Codable, CaseIterable { case miles, km }
enum BodyweightSource: String, Codable, CaseIterable { case healthKit, manual }
