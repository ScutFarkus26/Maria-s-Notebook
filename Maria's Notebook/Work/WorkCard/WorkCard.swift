import SwiftUI
import CoreData

/// Unified work display card supporting multiple display modes
struct WorkCard: View {
    let config: WorkCardConfig

    // MARK: - Configuration Types

    /// Type-safe configuration for all WorkCard display modes
    enum WorkCardConfig {
        case grid(GridConfig)
        case list(ListConfig)
        case pill(PillConfig)
        case compact(CompactConfig)

        var displayMode: WorkCardDisplayMode {
            switch self {
            case .grid: return .grid
            case .list: return .list
            case .pill: return .pill
            case .compact: return .compact
            }
        }
    }

    struct GridConfig {
        let work: CDWorkModel
        let lessonTitle: String
        let studentDisplay: String
        let needsAttention: Bool
        let ageSchoolDays: Int
        let onOpen: (CDWorkModel) -> Void
        let onMarkCompleted: (CDWorkModel) -> Void
        let onScheduleToday: (CDWorkModel) -> Void

        init(
            work: CDWorkModel,
            lessonTitle: String,
            studentDisplay: String,
            needsAttention: Bool = false,
            ageSchoolDays: Int = 0,
            onOpen: @escaping (CDWorkModel) -> Void,
            onMarkCompleted: @escaping (CDWorkModel) -> Void = { _ in },
            onScheduleToday: @escaping (CDWorkModel) -> Void = { _ in }
        ) {
            self.work = work
            self.lessonTitle = lessonTitle
            self.studentDisplay = studentDisplay
            self.needsAttention = needsAttention
            self.ageSchoolDays = ageSchoolDays
            self.onOpen = onOpen
            self.onMarkCompleted = onMarkCompleted
            self.onScheduleToday = onScheduleToday
        }
    }

    struct ListConfig {
        let work: CDWorkModel
        let title: String
        let subtitle: String
        let badge: WorkCardBadge?
        let onOpen: (CDWorkModel) -> Void

        init(
            work: CDWorkModel,
            title: String,
            subtitle: String,
            badge: WorkCardBadge? = nil,
            onOpen: @escaping (CDWorkModel) -> Void
        ) {
            self.work = work
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.onOpen = onOpen
        }
    }

    struct PillConfig {
        let item: ScheduledItem
        let nameForStudentID: (UUID) -> String
        let absentTodayIDs: Set<UUID>

        init(
            item: ScheduledItem,
            nameForStudentID: @escaping (UUID) -> String,
            absentTodayIDs: Set<UUID> = []
        ) {
            self.item = item
            self.nameForStudentID = nameForStudentID
            self.absentTodayIDs = absentTodayIDs
        }
    }

    struct CompactConfig {
        let work: CDWorkModel
        let title: String
        let workType: WorkCardWorkType
        let participants: [WorkCardParticipant]
        let onToggle: (CDWorkModel, UUID) -> Void

        init(
            work: CDWorkModel,
            title: String,
            workType: WorkCardWorkType,
            participants: [WorkCardParticipant],
            onToggle: @escaping (CDWorkModel, UUID) -> Void
        ) {
            self.work = work
            self.title = title
            self.workType = workType
            self.participants = participants
            self.onToggle = onToggle
        }
    }

    // MARK: - Initializer

    init(config: WorkCardConfig) {
        self.config = config
    }

    // MARK: - Body

    var body: some View {
        switch config {
        case .grid(let gridConfig):
            WorkCardGridContent(config: gridConfig)
        case .list(let listConfig):
            WorkCardListContent(config: listConfig)
        case .pill(let pillConfig):
            WorkCardPillContent(config: pillConfig)
        case .compact(let compactConfig):
            WorkCardCompactContent(config: compactConfig)
        }
    }
}

// MARK: - Convenience Factory Methods

extension WorkCard {
    /// Grid mode - replaces WorkCardView
    static func grid(
        work: CDWorkModel,
        lessonTitle: String,
        studentDisplay: String,
        needsAttention: Bool = false,
        ageSchoolDays: Int = 0,
        onOpen: @escaping (CDWorkModel) -> Void,
        onMarkCompleted: @escaping (CDWorkModel) -> Void = { _ in },
        onScheduleToday: @escaping (CDWorkModel) -> Void = { _ in }
    ) -> WorkCard {
        WorkCard(config: .grid(GridConfig(
            work: work,
            lessonTitle: lessonTitle,
            studentDisplay: studentDisplay,
            needsAttention: needsAttention,
            ageSchoolDays: ageSchoolDays,
            onOpen: onOpen,
            onMarkCompleted: onMarkCompleted,
            onScheduleToday: onScheduleToday
        )))
    }

    /// List mode - replaces inline rows in OpenWorkListView/WorksLogView
    static func list(
        work: CDWorkModel,
        title: String,
        subtitle: String,
        badge: WorkCardBadge? = nil,
        onOpen: @escaping (CDWorkModel) -> Void
    ) -> WorkCard {
        WorkCard(config: .list(ListConfig(
            work: work,
            title: title,
            subtitle: subtitle,
            badge: badge,
            onOpen: onOpen
        )))
    }

    /// Pill mode - replaces StudentWorkPill
    static func pill(
        item: ScheduledItem,
        nameForStudentID: @escaping (UUID) -> String,
        absentTodayIDs: Set<UUID> = []
    ) -> WorkCard {
        WorkCard(config: .pill(PillConfig(
            item: item,
            nameForStudentID: nameForStudentID,
            absentTodayIDs: absentTodayIDs
        )))
    }

    /// Compact mode - replaces LinkedWorkSection items
    static func compact(
        work: CDWorkModel,
        title: String,
        workType: WorkCardWorkType,
        participants: [WorkCardParticipant],
        onToggle: @escaping (CDWorkModel, UUID) -> Void
    ) -> WorkCard {
        WorkCard(config: .compact(CompactConfig(
            work: work,
            title: title,
            workType: workType,
            participants: participants,
            onToggle: onToggle
        )))
    }
}

// MARK: - Legacy Type Aliases (for backward compatibility)

extension WorkCard {
    typealias GridModeConfig = GridConfig
    typealias ListModeConfig = ListConfig
    typealias PillModeConfig = PillConfig
    typealias CompactModeConfig = CompactConfig
}
