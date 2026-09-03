import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

/// Discrete grade level used to bound a story's reading level.
/// Stored as raw String on `CDStory.gradeMinRaw` / `gradeMaxRaw`.
nonisolated public enum StoryGrade: String, CaseIterable, Sendable, Identifiable {
    case preK
    case kindergarten
    case first
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventhPlus

    public var id: String { rawValue }

    /// Ordering used for grade-band intersection logic. Lower = earlier.
    public var ordinal: Int {
        switch self {
        case .preK: return 0
        case .kindergarten: return 1
        case .first: return 2
        case .second: return 3
        case .third: return 4
        case .fourth: return 5
        case .fifth: return 6
        case .sixth: return 7
        case .seventhPlus: return 8
        }
    }

    public var shortLabel: String {
        switch self {
        case .preK: return "PreK"
        case .kindergarten: return "K"
        case .first: return "1"
        case .second: return "2"
        case .third: return "3"
        case .fourth: return "4"
        case .fifth: return "5"
        case .sixth: return "6"
        case .seventhPlus: return "7+"
        }
    }

    public var longLabel: String {
        switch self {
        case .preK: return "PreK"
        case .kindergarten: return "Kindergarten"
        case .first: return "1st"
        case .second: return "2nd"
        case .third: return "3rd"
        case .fourth: return "4th"
        case .fifth: return "5th"
        case .sixth: return "6th"
        case .seventhPlus: return "7th+"
        }
    }
}

/// A grade band representing a (possibly single-level) range from min to max.
nonisolated public struct StoryGradeBand: Hashable, Sendable {
    public let min: StoryGrade
    public let max: StoryGrade

    public init(min: StoryGrade, max: StoryGrade) {
        if min.ordinal <= max.ordinal {
            self.min = min
            self.max = max
        } else {
            self.min = max
            self.max = min
        }
    }

    public var displayName: String {
        if min == max { return min.longLabel }
        return "\(min.shortLabel)\u{2013}\(max.shortLabel)"
    }

    /// True if this band overlaps with another (for filtering).
    public func intersects(_ other: StoryGradeBand) -> Bool {
        min.ordinal <= other.max.ordinal && other.min.ordinal <= max.ordinal
    }

    /// Predefined buckets used by the filter chip bar.
    public static let filterBuckets: [StoryGradeBand] = [
        StoryGradeBand(min: .preK, max: .kindergarten),
        StoryGradeBand(min: .first, max: .second),
        StoryGradeBand(min: .third, max: .fourth),
        StoryGradeBand(min: .fifth, max: .sixth),
        StoryGradeBand(min: .seventhPlus, max: .seventhPlus)
    ]
}

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "A grade level appropriate for a children's story")
public enum StoryGradeAI: Equatable {
    case preK
    case kindergarten
    case first
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventhPlus

    var asStoryGrade: StoryGrade {
        switch self {
        case .preK: return .preK
        case .kindergarten: return .kindergarten
        case .first: return .first
        case .second: return .second
        case .third: return .third
        case .fourth: return .fourth
        case .fifth: return .fifth
        case .sixth: return .sixth
        case .seventhPlus: return .seventhPlus
        }
    }
}
#endif
