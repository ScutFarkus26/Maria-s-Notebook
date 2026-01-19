import SwiftUI
import SwiftData

/// Unified work display card supporting multiple display modes
struct WorkCard: View {
    let mode: WorkCardDisplayMode

    // Grid mode properties
    private var gridConfig: GridModeConfig?

    // List mode properties
    private var listConfig: ListModeConfig?

    // Pill mode properties
    private var pillConfig: PillModeConfig?

    // Compact mode properties
    private var compactConfig: CompactModeConfig?

    // MARK: - Grid Mode Config

    struct GridModeConfig {
        let work: WorkModel
        let lessonTitle: String
        let studentDisplay: String
        let needsAttention: Bool
        let ageSchoolDays: Int
        let onOpen: (WorkModel) -> Void
        let onMarkCompleted: (WorkModel) -> Void
        let onScheduleToday: (WorkModel) -> Void
    }

    // MARK: - List Mode Config

    struct ListModeConfig {
        let work: WorkModel
        let title: String
        let subtitle: String
        let badge: WorkCardBadge?
        let onOpen: (WorkModel) -> Void
    }

    // MARK: - Pill Mode Config

    struct PillModeConfig {
        let item: ScheduledItem
        let nameForStudentID: (UUID) -> String
        let absentTodayIDs: Set<UUID>
    }

    // MARK: - Compact Mode Config

    struct CompactModeConfig {
        let work: WorkModel
        let title: String
        let workType: WorkCardWorkType
        let participants: [WorkCardParticipant]
        let onToggle: (WorkModel, UUID) -> Void
    }

    // MARK: - Private Initializer

    private init(
        mode: WorkCardDisplayMode,
        gridConfig: GridModeConfig? = nil,
        listConfig: ListModeConfig? = nil,
        pillConfig: PillModeConfig? = nil,
        compactConfig: CompactModeConfig? = nil
    ) {
        self.mode = mode
        self.gridConfig = gridConfig
        self.listConfig = listConfig
        self.pillConfig = pillConfig
        self.compactConfig = compactConfig
    }

    // MARK: - Body

    var body: some View {
        switch mode {
        case .grid:
            if let config = gridConfig {
                WorkCardGridContent(config: config)
            }
        case .list:
            if let config = listConfig {
                WorkCardListContent(config: config)
            }
        case .pill:
            if let config = pillConfig {
                WorkCardPillContent(config: config)
            }
        case .compact:
            if let config = compactConfig {
                WorkCardCompactContent(config: config)
            }
        }
    }
}

// MARK: - Convenience Initializers

extension WorkCard {
    /// Grid mode - replaces WorkCardView
    static func grid(
        work: WorkModel,
        lessonTitle: String,
        studentDisplay: String,
        needsAttention: Bool,
        ageSchoolDays: Int,
        onOpen: @escaping (WorkModel) -> Void,
        onMarkCompleted: @escaping (WorkModel) -> Void = { _ in },
        onScheduleToday: @escaping (WorkModel) -> Void = { _ in }
    ) -> WorkCard {
        WorkCard(
            mode: .grid,
            gridConfig: GridModeConfig(
                work: work,
                lessonTitle: lessonTitle,
                studentDisplay: studentDisplay,
                needsAttention: needsAttention,
                ageSchoolDays: ageSchoolDays,
                onOpen: onOpen,
                onMarkCompleted: onMarkCompleted,
                onScheduleToday: onScheduleToday
            )
        )
    }

    /// List mode - replaces inline rows in OpenWorkListView/WorksLogView
    static func list(
        work: WorkModel,
        title: String,
        subtitle: String,
        badge: WorkCardBadge? = nil,
        onOpen: @escaping (WorkModel) -> Void
    ) -> WorkCard {
        WorkCard(
            mode: .list,
            listConfig: ListModeConfig(
                work: work,
                title: title,
                subtitle: subtitle,
                badge: badge,
                onOpen: onOpen
            )
        )
    }

    /// Pill mode - replaces StudentWorkPill
    static func pill(
        item: ScheduledItem,
        nameForStudentID: @escaping (UUID) -> String,
        absentTodayIDs: Set<UUID>
    ) -> WorkCard {
        WorkCard(
            mode: .pill,
            pillConfig: PillModeConfig(
                item: item,
                nameForStudentID: nameForStudentID,
                absentTodayIDs: absentTodayIDs
            )
        )
    }

    /// Compact mode - replaces LinkedWorkSection items
    static func compact(
        work: WorkModel,
        title: String,
        workType: WorkCardWorkType,
        participants: [WorkCardParticipant],
        onToggle: @escaping (WorkModel, UUID) -> Void
    ) -> WorkCard {
        WorkCard(
            mode: .compact,
            compactConfig: CompactModeConfig(
                work: work,
                title: title,
                workType: workType,
                participants: participants,
                onToggle: onToggle
            )
        )
    }
}
