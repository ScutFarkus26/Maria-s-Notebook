import SwiftUI

struct WorkViewSidebar: View {
    @Binding var filters: WorkFilters
    @Binding var isShowingStudentFilterPopover: Bool
    let subjects: [String]
    let students: [Student]
    let displayName: (Student) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Students")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Button {
                isShowingStudentFilterPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                    Text(filters.selectedStudentIDs.isEmpty ? "All Students" : "\(filters.selectedStudentIDs.count) selected")
                }
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingStudentFilterPopover, arrowEdge: .top) {
                StudentFilterView(
                    selectedStudentIDs: $filters.selectedStudentIDs,
                    students: students,
                    displayName: displayName,
                    onDismiss: { isShowingStudentFilterPopover = false }
                )
            }

            Text("Level")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "All",
                color: .accentColor,
                isSelected: filters.level == .all
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filters.level = .all
                }
            }

            SidebarFilterButton(
                icon: "circle.fill",
                title: "Lower",
                color: .blue,
                isSelected: filters.level == .lower
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filters.level = .lower
                }
            }

            SidebarFilterButton(
                icon: "circle.fill",
                title: "Upper",
                color: .pink,
                isSelected: filters.level == .upper
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filters.level = .upper
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes or lesson names", text: $filters.searchText)
                if !filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        filters.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.trailing, 16)

            // Group By section
            Text("Group By")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            ForEach(WorkFilters.Grouping.allCases, id: \.self) { grouping in
                SidebarFilterButton(
                    icon: grouping.icon,
                    title: grouping.displayName,
                    color: .accentColor,
                    isSelected: filters.grouping == grouping
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        filters.grouping = grouping
                    }
                }
            }

            Text("Subject")
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SidebarFilterButton(
                icon: "rectangle.3.group",
                title: "All Subjects",
                color: .accentColor,
                isSelected: filters.selectedSubject == nil
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                    filters.selectedSubject = nil
                }
            }

            ForEach(subjects, id: \.self) { subject in
                SidebarFilterButton(
                    icon: "folder.fill",
                    title: subject,
                    color: AppColors.color(forSubject: subject),
                    isSelected: filters.selectedSubject?.caseInsensitiveCompare(subject) == .orderedSame
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                        filters.selectedSubject = subject
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .frame(width: 200, alignment: .topLeading)
        .background(Color.gray.opacity(0.08))
    }
}
