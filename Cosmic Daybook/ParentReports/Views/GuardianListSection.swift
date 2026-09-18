// GuardianListSection.swift
// Parent/guardian contacts shown on the student overview tab.

import SwiftUI
import CoreData

struct GuardianListSection: View {
    let student: CDStudent

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var guardians: FetchedResults<CDGuardian>
    @State private var editingGuardian: CDGuardian?
    @State private var showingAddSheet = false

    init(student: CDStudent) {
        self.student = student
        _guardians = FetchRequest(
            fetchRequest: CDGuardian.fetchRequest(studentID: student.id?.uuidString ?? ""),
            animation: .default
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Parents & Guardians")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Add guardian")
            }
            .padding(.horizontal, AppTheme.Spacing.xsmall)

            if guardians.isEmpty {
                Text("No guardian contacts yet. Add one to send progress reports.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.vertical, AppTheme.Spacing.compact)
            } else {
                ForEach(guardians) { guardian in
                    Button {
                        editingGuardian = guardian
                    } label: {
                        GuardianRow(guardian: guardian)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppTheme.Spacing.xsmall)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .sheet(isPresented: $showingAddSheet) {
            GuardianEditSheet(studentID: student.id?.uuidString ?? "", guardian: nil)
        }
        .sheet(item: $editingGuardian) { guardian in
            GuardianEditSheet(studentID: student.id?.uuidString ?? "", guardian: guardian)
        }
    }
}

private struct GuardianRow: View {
    let guardian: CDGuardian

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Text(guardian.name.isEmpty ? "Unnamed" : guardian.name)
                        .font(.body)
                    Text(guardian.relationship.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !guardian.email.isEmpty {
                    Text(guardian.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if !guardian.receivesReports {
                Text("No reports")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, AppTheme.Spacing.xsmall)
    }
}
