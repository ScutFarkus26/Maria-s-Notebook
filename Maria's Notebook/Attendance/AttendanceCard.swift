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
    @State private var draftNote: String = ""

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

    private var hasNote: Bool {
        let t = record?.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !t.isEmpty
    }

    // Original layout: note icon next to name (macOS and iOS regular)
    @ViewBuilder
    private var originalLayout: some View {
        HStack(spacing: 8) {
            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            // Small note icon at far right (only when no note exists and editing)
            if !hasNote && isEditing {
                Button {
                    draftNote = record?.note ?? ""
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
        HStack(spacing: 6) {
            Text(statusLabel)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor)
            if status == .absent && absenceReason != .none {
                Image(systemName: absenceReason.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(accentColor.opacity(0.12))
        )

        // Clicking the note opens the editor only if editing, otherwise static display
        if hasNote {
            if isEditing {
                Button {
                    draftNote = record?.note ?? ""
                    showingNoteEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text(record?.note ?? "")
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
                    Text(record?.note ?? "")
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
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
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
                    // iPhone compact layout: name on separate row, note at bottom
                    // Name on its own row, can wrap to 2 lines
                    Text(student.fullName)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Compact status pill with absence reason indicator
                    HStack(spacing: 6) {
                        Text(statusLabel)
                            .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor)
                        if status == .absent && absenceReason != .none {
                            Image(systemName: absenceReason.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(accentColor)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(accentColor.opacity(0.12))
                    )

                    // Spacer to push note section to bottom
                    Spacer(minLength: 4)

                    // Note section at bottom: either add note icon or note text
                    if !hasNote && isEditing {
                        // Add note icon button
                        Button {
                            draftNote = record?.note ?? ""
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
                        // Note text display
                        if isEditing {
                            Button {
                                draftNote = record?.note ?? ""
                                showingNoteEditor = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "note.text")
                                        .foregroundStyle(.secondary)
                                    Text(record?.note ?? "")
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
                                Text(record?.note ?? "")
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                } else {
                    // iOS regular layout: original layout (same as macOS)
                    originalLayout
                }
#else
                // macOS: original layout
                originalLayout
#endif
            }
            .padding(10)
        }
        .frame(minHeight: 88)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
#if os(macOS)
        .highPriorityGesture(TapGesture(count: 1).onEnded { if isEditing { onTap() } })
#else
        .onTapGesture { if isEditing { onTap() } }
#endif
        .contextMenu {
            if isEditing {
                Button {
                    draftNote = record?.note ?? ""
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
            NoteEditorSheet(initialNote: record?.note ?? "") { newNote in
                onEditNote(newNote)
                showingNoteEditor = false
            } onCancel: {
                showingNoteEditor = false
            }
#if os(macOS)
            .frame(minWidth: 420, minHeight: 220)
            .presentationSizingFitted()
#endif
        }
    }
}

// MARK: - Note Editor
private struct NoteEditorSheet: View {
    @State private var text: String
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    init(initialNote: String, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialNote)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Note")
                .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
            TextField("Optional note", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

