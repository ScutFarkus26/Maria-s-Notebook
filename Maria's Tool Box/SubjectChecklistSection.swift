import SwiftUI

struct SubjectChecklistSection: View {
    let subject: String
    let orderedGroups: [String]
    let lessons: [Lesson]

    let rowStatesByLesson: [UUID: StudentChecklistRowState]

    let onTapScheduled: (Lesson, StudentChecklistRowState?) -> Void
    let onTapPresented: (Lesson, StudentChecklistRowState?) -> Void
    let onTapActive: (Lesson, StudentChecklistRowState?) -> Void
    let onTapComplete: (Lesson, StudentChecklistRowState?) -> Void

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
                                        let row = rowStatesByLesson[lesson.id]
                                        let isScheduled = row?.isScheduled ?? false
                                        let isPresented = row?.isPresented ?? false
                                        let isActive = row?.isActive ?? false
                                        let isComplete = row?.isComplete ?? false
                                        let isStale = (row?.isStale ?? false) && !isComplete

                                        HStack(spacing: 12) {
                                            LifecycleIndicatorView(
                                                wasPresented: isPresented,
                                                hasPending: (isActive && !isComplete),
                                                isPlanned: isScheduled
                                            )
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
                                                Button {
                                                    onTapScheduled(lesson, row)
                                                } label: {
                                                    Image(systemName: "calendar.badge.plus")
                                                        .foregroundStyle(isScheduled ? Color.green : Color.secondary)
                                                        .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .help(isScheduled ? "Planned — open Student Lesson to adjust schedule" : "Plan/Schedule this lesson")

                                                Button {
                                                    onTapPresented(lesson, row)
                                                } label: {
                                                    ZStack {
                                                        if !isPresented && isScheduled {
                                                            Circle()
                                                                .stroke(Color.green, lineWidth: 1)
                                                        }
                                                        Image(systemName: "checkmark")
                                                            .foregroundStyle(isPresented ? Color.green : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .help(isScheduled ? "Planned — tap to mark presented or open details" : (isPresented ? "Presented — tap to review or unmark" : "Mark as presented"))

                                                Button {
                                                    onTapActive(lesson, row)
                                                } label: {
                                                    Image(systemName: "hammer")
                                                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                                                        .frame(width: 22, height: 22)
                                                        .overlay {
                                                            if isActive && isStale {
                                                                Circle()
                                                                    .fill(Color.orange)
                                                                    .frame(width: 6, height: 6)
                                                                    .offset(x: 8, y: -8)
                                                            }
                                                        }
                                                }
                                                .buttonStyle(.plain)
                                                .help(!isActive ? "No active work" : (isStale ? "Active but stale — tap to update" : "Active work"))

                                                Button {
                                                    onTapComplete(lesson, row)
                                                } label: {
                                                    Image(systemName: "checkmark.circle")
                                                        .foregroundStyle(isComplete ? Color.green : Color.secondary)
                                                        .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .help(isComplete ? "Completed — tap to toggle" : "Mark as complete")
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
