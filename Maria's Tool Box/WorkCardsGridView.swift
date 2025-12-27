import SwiftUI
import Foundation

struct WorkCardsGridView: View {
    let works: [WorkModel]
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    let onTapWork: ((WorkModel) -> Void)?
    let onToggleComplete: ((WorkModel) -> Void)?
    let hideTypeBadge: Bool
    let embedInScrollView: Bool

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif
    private var isCompactWidth: Bool {
        #if os(iOS)
        return hSizeClass == .compact
        #else
        return false
        #endif
    }

    init(
        works: [WorkModel],
        studentsByID: [UUID: Student],
        lessonsByID: [UUID: Lesson],
        studentLessonsByID: [UUID: StudentLesson],
        onTapWork: ((WorkModel) -> Void)? = nil,
        onToggleComplete: ((WorkModel) -> Void)? = nil,
        embedInScrollView: Bool = true,
        hideTypeBadge: Bool = false
    ) {
        self.works = works
        self.studentsByID = studentsByID
        self.lessonsByID = lessonsByID
        self.studentLessonsByID = studentLessonsByID
        self.onTapWork = onTapWork
        self.onToggleComplete = onToggleComplete
        self.embedInScrollView = embedInScrollView
        self.hideTypeBadge = hideTypeBadge
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 24)
    ]

    var body: some View {
        Group {
            if embedInScrollView {
                ScrollView { gridContent }
            } else {
                gridContent
            }
        }
    }

    private var gridContent: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(works, id: \.id) { work in
                WorkCard(
                    work: work,
                    studentsByID: studentsByID,
                    lessonsByID: lessonsByID,
                    studentLessonsByID: studentLessonsByID,
                    onToggleComplete: onToggleComplete,
                    hideTypeBadge: hideTypeBadge
                )
                .contentShape(Rectangle())
                .onTapGesture { onTapWork?(work) }
            }
        }
        .padding(24)
    }
    
    private var listContent: some View {
        List {
            ForEach(works, id: \.id) { work in
                WorkRow(
                    work: work,
                    studentsByID: studentsByID,
                    lessonsByID: lessonsByID,
                    studentLessonsByID: studentLessonsByID,
                    onToggleComplete: onToggleComplete,
                    hideTypeBadge: hideTypeBadge
                )
                .contentShape(Rectangle())
                .onTapGesture { onTapWork?(work) }
            }
        }
        .listStyle(.plain)
    }
    
    private var listContentNoScroll: some View {
        VStack {
            ForEach(works, id: \.id) { work in
                WorkRow(
                    work: work,
                    studentsByID: studentsByID,
                    lessonsByID: lessonsByID,
                    studentLessonsByID: studentLessonsByID,
                    onToggleComplete: onToggleComplete,
                    hideTypeBadge: hideTypeBadge
                )
                .contentShape(Rectangle())
                .onTapGesture { onTapWork?(work) }
                Divider()
            }
        }
    }
}

private struct WorkCard: View {
    let work: WorkModel
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    let onToggleComplete: ((WorkModel) -> Void)?
    let hideTypeBadge: Bool

    private var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] {
        Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var workTypeColor: Color {
        switch work.workType {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }

    private var workTypeBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(workTypeColor).frame(width: 6, height: 6)
            Text(work.workType.rawValue)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(workTypeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(workTypeColor.opacity(0.12)))
        .accessibilityLabel("Work type: \(work.workType.rawValue)")
    }

    private var linkedLessonLine: String {
        guard let slID = work.studentLessonID, let snap = studentLessonSnapshotsByID[slID] else { return "" }
        let lessonName = lessonsByID[snap.lessonID]?.name ?? "Lesson"
        let date = snap.scheduledFor ?? snap.givenAt ?? snap.createdAt
        let dateString = date.formatted(date: .numeric, time: .omitted)
        return "\(lessonName) • \(dateString)"
    }

    private var activeStudentNames: [String] {
        (work.participants ?? []).compactMap { p -> String? in
            guard let s = studentsByID[p.studentID] else { return nil }
            guard p.completedAt == nil else { return nil }
            let parts = s.fullName.split(separator: " ")
            guard let first = parts.first else { return s.fullName }
            let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
            return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
        }
    }

    private var completedCount: Int {
        (work.participants ?? []).filter { $0.completedAt != nil }.count
    }
    
    private var isFullyComplete: Bool {
        let total = (work.participants ?? []).count
        return total > 0 && completedCount == total
    }
    
    private var progress: Double {
        let total = max((work.participants ?? []).count, 1)
        return Double(completedCount) / Double(total)
    }
    
    private var progressRing: some View {
        ZStack {
            if isFullyComplete {
                ZStack {
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("All students complete")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .accessibilityLabel("\(completedCount) of \(work.participants?.count ?? 0) students complete")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: isFullyComplete)
    }

    private var studentsLineView: some View {
        HStack(spacing: 4) {
            if !activeStudentNames.isEmpty {
                Text(activeStudentNames.count <= 3 ? activeStudentNames.joined(separator: ", ") : activeStudentNames.prefix(3).joined(separator: ", ") + ", +\(activeStudentNames.count - 3)")
            }
            if completedCount > 0 {
                Text("• \(completedCount) done")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var notesText: String {
        work.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var titleText: String {
        work.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !titleText.isEmpty {
                    Text(titleText)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                } else {
                    Text(work.createdAt, style: .date)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                }
                progressRing
                Spacer(minLength: 0)
                if !hideTypeBadge { workTypeBadge }
            }
            if !titleText.isEmpty {
                Text(work.createdAt, style: .date)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            studentsLineView

            if !linkedLessonLine.isEmpty {
                Text(linkedLessonLine)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !notesText.isEmpty {
                Text(notesText)
                    .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}

private struct WorkRow: View {
    let work: WorkModel
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    let onToggleComplete: ((WorkModel) -> Void)?
    let hideTypeBadge: Bool

    private var studentLessonSnapshotsByID: [UUID: StudentLessonSnapshot] {
        Dictionary(uniqueKeysWithValues: studentLessonsByID.map { ($0.key, $0.value.snapshot()) })
    }

    private var workTypeColor: Color {
        switch work.workType {
        case .research: return .teal
        case .followUp: return .orange
        case .practice: return .purple
        }
    }

    private var linkedLessonLine: String {
        guard let slID = work.studentLessonID, let snap = studentLessonSnapshotsByID[slID] else { return "" }
        let lessonName = lessonsByID[snap.lessonID]?.name ?? "Lesson"
        let date = snap.scheduledFor ?? snap.givenAt ?? snap.createdAt
        let dateString = date.formatted(date: .numeric, time: .omitted)
        return "\(lessonName) • \(dateString)"
    }

    private var activeStudentNames: [String] {
        (work.participants ?? []).compactMap { p -> String? in
            guard let s = studentsByID[p.studentID] else { return nil }
            guard p.completedAt == nil else { return nil }
            let parts = s.fullName.split(separator: " ")
            guard let first = parts.first else { return s.fullName }
            let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
            return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
        }
    }

    private var completedCount: Int {
        (work.participants ?? []).filter { $0.completedAt != nil }.count
    }

    private var isFullyComplete: Bool {
        let total = (work.participants ?? []).count
        return total > 0 && completedCount == total
    }

    private var progress: Double {
        let total = max((work.participants ?? []).count, 1)
        return Double(completedCount) / Double(total)
    }

    private var progressRing: some View {
        ZStack {
            if isFullyComplete {
                ZStack {
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("All students complete")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .accessibilityLabel("\(completedCount) of \(work.participants?.count ?? 0) students complete")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1), value: isFullyComplete)
    }

    private var studentsLineView: some View {
        HStack(spacing: 4) {
            if !activeStudentNames.isEmpty {
                Text(activeStudentNames.count <= 3 ? activeStudentNames.joined(separator: ", ") : activeStudentNames.prefix(3).joined(separator: ", ") + ", +\(activeStudentNames.count - 3)")
            }
            if completedCount > 0 {
                Text("• \(completedCount) done")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var notesText: String {
        work.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titleText: String {
        work.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !titleText.isEmpty {
                        Text(titleText)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    } else {
                        Text(work.createdAt, style: .date)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    if !hideTypeBadge {
                        Text(work.workType.rawValue)
                            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                            .foregroundStyle(workTypeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(workTypeColor.opacity(0.12)))
                    }
                }
                if !titleText.isEmpty {
                    Text(work.createdAt, style: .date)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                studentsLineView
                if !linkedLessonLine.isEmpty {
                    Text(linkedLessonLine)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !notesText.isEmpty {
                    Text(notesText)
                        .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            progressRing
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    let studentA = Student(firstName: "Alex", lastName: "Rivera", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    let studentB = Student(firstName: "Blair", lastName: "Chen", birthday: Date(timeIntervalSince1970: 0), level: .lower)
    let lesson = Lesson(name: "Decimal System", subject: "Math", group: "Number Work", subheading: "Intro", writeUp: "")
    let sl = StudentLesson(lessonID: lesson.id, studentIDs: [studentA.id, studentB.id])
    let work = WorkModel(workType: .practice, studentLessonID: sl.id, notes: "Practiced with golden beads.")
    work.participants = [
        WorkParticipantEntity(studentID: studentA.id),
        WorkParticipantEntity(studentID: studentB.id)
    ]

    return WorkCardsGridView(
        works: [work],
        studentsByID: [studentA.id: studentA, studentB.id: studentB],
        lessonsByID: [lesson.id: lesson],
        studentLessonsByID: [sl.id: sl]
    )
}

