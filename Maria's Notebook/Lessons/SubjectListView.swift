// SubjectListView.swift
// Column 1 of the 3-column NavigationSplitView: Displays all subjects as a list.
// Subjects are derived from existing Lesson data using LessonsViewModel.

import SwiftUI

struct SubjectListView: View {
    let subjects: [String]
    let selectedSubject: String?
    let onSelectSubject: (String?) -> Void
    
    var body: some View {
        List(selection: Binding(
            get: { selectedSubject },
            set: { onSelectSubject($0) }
        )) {
            ForEach(subjects, id: \.self) { subject in
                SubjectListRow(subject: subject)
                    .tag(subject)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Subjects")
    }
}

private struct SubjectListRow: View {
    let subject: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(AppColors.color(forSubject: subject))
                .font(.system(size: 16))
            Text(subject)
                .font(.system(size: AppTheme.FontSize.body, weight: .regular, design: .rounded))
        }
        .padding(.vertical, 4)
    }
}

