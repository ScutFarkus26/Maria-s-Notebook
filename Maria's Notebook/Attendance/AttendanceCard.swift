// AttendanceCard.swift
// Attendance card component extracted from AttendanceView

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AttendanceCard: View {
    let student: Student
    let record: AttendanceRecord?
    let isEditing: Bool
    let onTap: () -> Void
    let onEditNote: (String?) -> Void
    let onSetAbsenceReason: ((AbsenceReason) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showingNoteEditor = false
    @State private var noteToEdit: Note? = nil

    private var status: AttendanceStatus { record?.status ?? .unmarked }
    private var absenceReason: AbsenceReason { record?.absenceReason ?? .none }

    private var statusLabel: String { status.displayName }

    private var accentColor: Color {
        switch status {
        case .present: return .green
        case .tardy: return .blue
        case .absent: return .red
        case .leftEarly: return .purple
        case .unmarked: return .gray.opacity(0.4)
        }
    }

    // Helper to resolve the most relevant note content from unified notes
    private var resolvedNote: (text: String, object: Note?) {
        guard let record else { return ("", nil) }
        let note = Note.latestNote(in: record.notes)
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
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .medium, design: .rounded))
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
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
        .animation(.bouncy(duration: 0.3, extraBounce: 0.2), value: status)

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
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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
    
    @ViewBuilder
    private var compactLayout: some View {
        // iPhone compact layout
        HStack(spacing: 6) {
            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .medium, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // Visual indicator for note
            if hasNote {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Compact status pill with absence reason indicator
        HStack(spacing: 6) {
            Text(statusLabel)
                .id(status)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
            if status == .absent && absenceReason != .none {
                Image(systemName: absenceReason.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.statusPillVertical)
        .background(
            Capsule().fill(accentColor.opacity(UIConstants.OpacityConstants.medium))
        )
        .animation(.bouncy(duration: 0.3, extraBounce: 0.2), value: status)

        // Spacer to push note section to bottom
        Spacer(minLength: 4)

        // Note section at bottom
        if !hasNote && isEditing {
            // Add note icon button
            Button {
                noteToEdit = nil
                showingNoteEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    Text("Add Note")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Note")
        } else if hasNote {
            let noteContent = resolvedNote
            // Note text display
            if isEditing {
                Button {
                    noteToEdit = noteContent.object
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text(noteContent.text)
                            .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
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
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
    
    @ViewBuilder
    private var regularLayout: some View {
        // iOS regular layout and macOS: original layout
        originalLayout
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar indicating status color
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 8) {
#if os(iOS)
                if hSizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
#else
                regularLayout
#endif
            }
            .padding(10)
        }
        .frame(minHeight: 80)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: status)
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { if isEditing { onTap() } })
#else
        .onTapGesture { if isEditing { onTap() } }
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
        .sheet(isPresented: $showingNoteEditor) {
            if let record = record {
                UnifiedNoteEditor(
                    context: .attendance(record),
                    initialNote: noteToEdit,
                    onSave: { _ in
                        // Note is automatically saved via relationship
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
