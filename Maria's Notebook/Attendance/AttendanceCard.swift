// AttendanceCard.swift
// Attendance card component extracted from AttendanceView

import SwiftUI
import CoreData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// swiftlint:disable:next type_body_length
struct AttendanceCard: View {
    let student: CDStudent
    let record: CDAttendanceRecord?
    let isEditing: Bool
    let onTap: () -> Void
    let onEditNote: (String?) -> Void
    let onSetAbsenceReason: ((AbsenceReason) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showingNoteEditor = false
    @State private var noteToEdit: CDNote?

    private var status: AttendanceStatus { record?.status ?? .unmarked }
    private var absenceReason: AbsenceReason { record?.absenceReason ?? .none }

    private var statusLabel: String { status.displayName }

    private var accentColor: Color {
        switch status {
        case .present: return .green
        case .tardy: return .blue
        case .absent: return .red
        case .leftEarly: return .purple
        case .unmarked: return .gray.opacity(UIConstants.OpacityConstants.muted)
        }
    }

    // Helper to resolve the most relevant note content from unified notes
    private var resolvedNote: (text: String, object: CDNote?) {
        guard let record else { return ("", nil) }
        let note = CDNote.latestNote(in: (record.notes?.allObjects as? [CDNote]) ?? [])
        return (note?.body ?? "", note)
    }

    private var hasNote: Bool {
        return !resolvedNote.text.isEmpty
    }

    // Original layout: note icon next to name (macOS and iOS regular)
    @ViewBuilder
    private var originalLayout: some View {
        HStack(spacing: 8) {
            Text(student.fullName)
                .font(AppTheme.ScaledFont.titleSmall)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // Visual indicator that a note exists
            if hasNote {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            // Small note icon at far right (only when no note exists and editing)
            if !hasNote && isEditing {
                Button {
                    noteToEdit = nil
                    showingNoteEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Add Note")
                }
                .buttonStyle(.plain)
            }
        }

        // Compact status pill with absence reason indicator
        StatusPill(
            text: statusLabel,
            color: accentColor,
            icon: (status == .absent && absenceReason != .none) ? absenceReason.icon : nil
        )
        .id(status)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
        .adaptiveAnimation(.bouncy(duration: 0.3, extraBounce: 0.2), value: status)

        // Clicking the note opens the editor only if editing, otherwise static display
        if hasNote {
            let noteContent = resolvedNote
            
            if isEditing {
                Button {
                    noteToEdit = noteContent.object
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text(noteContent.text)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.plain)
                .help("Edit note")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                    Text(noteContent.text)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var background: some View {
        // Neutral card background with subtle elevation
        let bgColor: Color = {
#if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
#else
            return Color(uiColor: .systemBackground)
#endif
        }()

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(bgColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle), lineWidth: 1)
            )
    }

    // MARK: - Layout Variants

    // Status circle icon for compact row layout (Reminders-style)
    private var statusIconName: String {
        switch status {
        case .unmarked: return "circle"
        case .present: return "checkmark.circle.fill"
        case .absent: return "xmark.circle.fill"
        case .tardy: return "clock.fill"
        case .leftEarly: return "arrow.right.circle.fill"
        }
    }

    @ViewBuilder
    private var compactLayout: some View {
        // Reminders-style list row: status circle | name + details | note indicator
        HStack(spacing: AppTheme.Spacing.compact) {
            // Tappable status circle
            Button {
                if isEditing { onTap() }
            } label: {
                Image(systemName: statusIconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .id(status)
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
            .adaptiveAnimation(.bouncy(duration: 0.3, extraBounce: 0.2), value: status)

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(AppTheme.ScaledFont.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Status label + absence reason on one line
                HStack(spacing: 4) {
                    Text(statusLabel)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(accentColor)
                    if status == .absent && absenceReason != .none {
                        Image(systemName: absenceReason.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(accentColor)
                        Text(absenceReason.displayName)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(accentColor)
                    }
                }
            }

            Spacer(minLength: 0)

            // Trailing: note indicator or add-note button
            if hasNote {
                let noteContent = resolvedNote
                if isEditing {
                    Button {
                        noteToEdit = noteContent.object
                        showingNoteEditor = true
                    } label: {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            } else if isEditing {
                Button {
                    noteToEdit = nil
                    showingNoteEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppTheme.Spacing.small)
        .padding(.horizontal, AppTheme.Spacing.medium)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var regularLayout: some View {
        // iOS regular layout and macOS: original layout
        originalLayout
    }

    // MARK: - Card body (grid layout for iPad/macOS)
    private var cardBody: some View {
        HStack(spacing: 0) {
            // Left accent bar indicating status color
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 8) {
                regularLayout
            }
            .padding(10)
        }
        .frame(minHeight: 80)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .adaptiveAnimation(.spring(response: 0.4, dampingFraction: 0.7), value: status)
    }

    var body: some View {
        Group {
#if os(iOS)
            if hSizeClass == .compact {
                compactLayout
            } else {
                cardBody
            }
#else
            cardBody
#endif
        }
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { if isEditing { onTap() } })
#else
        .onTapGesture {
            // Only handle tap for non-compact (card) layout; compact uses the circle button
            if hSizeClass != .compact && isEditing { onTap() }
        }
#endif
        .contextMenu {
            if isEditing {
                Button {
                    noteToEdit = resolvedNote.object
                    showingNoteEditor = true
                } label: {
                    Label("Note…", systemImage: "square.and.pencil")
                }

                // Absence reason options (only show when status is absent)
                if status == .absent, let onSetAbsenceReason = onSetAbsenceReason {
                    Divider()

                    Button {
                        onSetAbsenceReason(.sick)
                    } label: {
                        Label("Mark as Sick", systemImage: "cross.case.fill")
                    }

                    Button {
                        onSetAbsenceReason(.vacation)
                    } label: {
                        Label("Mark as Vacation", systemImage: "beach.umbrella.fill")
                    }

                    if absenceReason != .none {
                        Button {
                            onSetAbsenceReason(.none)
                        } label: {
                            Label("Clear Reason", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(student.fullName), \(statusLabel)")
        .accessibilityValue(hasNote ? "Has note" : "No note")
        .accessibilityHint(isEditing ? "Double tap to change attendance status" : "")
        .sheet(isPresented: $showingNoteEditor) {
            if let record {
                UnifiedNoteEditor(
                    context: .attendance(record),
                    initialNote: noteToEdit,
                    onSave: { _ in
                        // CDNote is automatically saved via relationship
                        showingNoteEditor = false
                    },
                    onCancel: {
                        showingNoteEditor = false
                    }
                )
            }
        }
    }
}
