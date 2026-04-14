// TodayViewRecentNotesSection.swift
// Recent observations section for TodayView — surfaces yesterday's notes
// so the guide can review them before planning today's lessons.

import SwiftUI

extension TodayView {

    // MARK: - Recent Notes Section

    var recentNotesListSection: some View {
        Section {
            if viewModel.recentNotes.isEmpty {
                emptyStateText("No recent observations")
            } else {
                ForEach(viewModel.recentNotes, id: \.objectID) { note in
                    recentNoteRow(note)
                        .id(note.id)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            noteBeingEdited = note
                        }
                }
            }
        } header: {
            recentNotesSectionHeader
        }
    }

    @ViewBuilder
    private func recentNoteRow(_ note: CDNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Category indicator
                Image(systemName: noteCategoryIcon(note.category))
                    .font(.system(size: 11))
                    .foregroundStyle(noteCategoryColor(note.category))

                // Student names
                Text(noteStudentLabel(note))
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)

                Spacer()

                // Relative date
                if let createdAt = note.createdAt {
                    Text(createdAt, style: .relative)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Note body preview
            Text(note.body.prefix(120))
                .font(AppTheme.ScaledFont.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Flags
            HStack(spacing: 8) {
                if note.needsFollowUp {
                    Label("Follow-up", systemImage: "flag.fill")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.orange)
                }
                if note.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var recentNotesSectionHeader: some View {
        HStack {
            Text("Recent Observations")
                .font(AppTheme.ScaledFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            if !viewModel.recentNotes.isEmpty {
                Text("\(viewModel.recentNotes.count)")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(UIConstants.OpacityConstants.moderate)))
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func noteStudentLabel(_ note: CDNote) -> String {
        switch note.scope {
        case .all:
            return "All Students"
        case .student(let id):
            if let student = viewModel.recentNoteStudentsByID[id] {
                return StudentFormatter.displayName(for: student)
            }
            return "Student"
        case .students(let ids):
            let names = ids.compactMap { viewModel.recentNoteStudentsByID[$0] }
                .map { StudentFormatter.displayName(for: $0) }
            if names.isEmpty { return "\(ids.count) students" }
            if names.count <= 2 { return names.joined(separator: ", ") }
            return "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    private func noteCategoryIcon(_ category: NoteCategory) -> String {
        switch category {
        case .academic: return "book.fill"
        case .behavioral: return "person.fill"
        case .social: return "person.2.fill"
        case .emotional: return "heart.fill"
        case .health: return "cross.fill"
        case .attendance: return "clock.fill"
        case .general: return "note.text"
        }
    }

    private func noteCategoryColor(_ category: NoteCategory) -> Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .green
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .purple
        case .general: return .gray
        }
    }
}
