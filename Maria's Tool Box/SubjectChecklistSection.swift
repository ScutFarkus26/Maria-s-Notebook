import SwiftUI

struct SubjectChecklistSection: View {
    let subject: String
    let orderedGroups: [String]
    let lessons: [Lesson]

    // Derived state
    let masteredLessonIDs: Set<UUID>
    let pendingWorkLessonIDs: Set<UUID>
    let plannedLessonIDs: Set<UUID>
    let practiceLessonIDs: Set<UUID>
    let pendingPracticeLessonIDs: Set<UUID>
    let followUpLessonIDs: Set<UUID>
    let pendingFollowUpLessonIDs: Set<UUID>

    // Actions
    let onTogglePresented: (Lesson) -> Void
    let onOpenMastered: (Lesson) -> Void
    let onOpenPlan: (Lesson) -> Void
    let onTogglePractice: (Lesson) -> Void
    let onOpenPractice: (Lesson) -> Void
    let onToggleFollowUp: (Lesson) -> Void
    let onOpenFollowUp: (Lesson) -> Void

    private func lessonsIn(group: String) -> [Lesson] {
        let sub = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupTrimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(sub) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(groupTrimmed) == .orderedSame
        }
        return filtered.sorted { lhs, rhs in
            if lhs.orderInGroup == rhs.orderInGroup {
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                return nameOrder == .orderedAscending
            }
            return lhs.orderInGroup < rhs.orderInGroup
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(subject) Checklist")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
            }
            .padding(.top, 4)

            if orderedGroups.isEmpty {
                ContentUnavailableView(
                    "No \(subject) Lessons",
                    systemImage: "text.book.closed",
                    description: Text("Add lessons in Albums to see them here.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(orderedGroups, id: \.self) { group in
                        let items = lessonsIn(group: group)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(AppColors.color(forSubject: subject))
                                    Text(group)
                                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                                }
                                VStack(spacing: 8) {
                                    ForEach(items, id: \.id) { lesson in
                                        let wasPresented = masteredLessonIDs.contains(lesson.id)
                                        let hasPending = pendingWorkLessonIDs.contains(lesson.id)
                                        let isPlanned = plannedLessonIDs.contains(lesson.id)

                                        HStack(spacing: 12) {
                                            LifecycleIndicatorView(wasPresented: wasPresented, hasPending: hasPending, isPlanned: isPlanned)
                                                .frame(width: 22, height: 22)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(lesson.name)
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                if !lesson.subheading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                    Text(lesson.subheading)
                                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer(minLength: 0)

                                            HStack(spacing: 10) {
                                                Button { onOpenPlan(lesson) } label: {
                                                    Image(systemName: "calendar.badge.plus")
                                                        .foregroundStyle(isPlanned ? Color.green : Color.secondary)
                                                        .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .help(isPlanned ? "Planned — open Give Lesson to adjust schedule" : "Plan/Schedule this lesson")

                                                Button { onTogglePresented(lesson) } label: {
                                                    ZStack {
                                                        if !wasPresented && isPlanned {
                                                            Circle()
                                                                .stroke(Color.green, lineWidth: 1)
                                                        }
                                                        Image(systemName: "checkmark")
                                                            .foregroundStyle(wasPresented ? Color.green : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Presentation Details…") { onOpenMastered(lesson) }
                                                    Button("Plan Presentation…") { onOpenPlan(lesson) }
                                                }
                                                .help(isPlanned ? "Planned — tap to mark presented or open details" : (wasPresented ? "Presented — tap to review or unmark" : "Mark as presented"))

                                                Button { onTogglePractice(lesson) } label: {
                                                    let hasPractice = practiceLessonIDs.contains(lesson.id)
                                                    let isPendingPractice = pendingPracticeLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasPractice && isPendingPractice {
                                                            Circle()
                                                                .stroke(Color.purple, lineWidth: 2)
                                                                .frame(width: 18, height: 18)
                                                        }
                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                            .foregroundStyle(hasPractice && !isPendingPractice ? Color.purple : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Practice Work…") { onOpenPractice(lesson) }
                                                }
                                                .help(!practiceLessonIDs.contains(lesson.id) ? "Add practice work" : (pendingPracticeLessonIDs.contains(lesson.id) ? "Practice pending — tap to mark complete or open work" : "Practice completed — tap to toggle or open work"))

                                                Button { onToggleFollowUp(lesson) } label: {
                                                    let hasFollowUp = followUpLessonIDs.contains(lesson.id)
                                                    let isPendingFollowUp = pendingFollowUpLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasFollowUp && isPendingFollowUp {
                                                            Circle()
                                                                .stroke(Color.orange, lineWidth: 2)
                                                                .frame(width: 18, height: 18)
                                                        }
                                                        Image(systemName: "bolt.fill")
                                                            .foregroundStyle(hasFollowUp && !isPendingFollowUp ? Color.orange : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Follow Up Work…") { onOpenFollowUp(lesson) }
                                                }
                                                .help(!followUpLessonIDs.contains(lesson.id) ? "Add follow-up work" : (pendingFollowUpLessonIDs.contains(lesson.id) ? "Follow-up pending — tap to mark complete or open work" : "Follow-up completed — tap to toggle or open work"))
                                            }
                                            .frame(minWidth: 0)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    Text("SubjectChecklistSection requires live data")
}
