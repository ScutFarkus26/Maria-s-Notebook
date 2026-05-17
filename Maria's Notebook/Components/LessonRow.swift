// LessonRow.swift
// Shared component for displaying lesson rows in list views

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LessonRow: View {
    let lesson: CDLesson

    /// The style of secondary text to display
    enum SecondaryTextStyle {
        case areaAndSequence  // Shows "area · sequence"
        case section       // Shows section if present
    }

    let secondaryTextStyle: SecondaryTextStyle
    let showTagIcon: Bool

    // MARK: - Context Menu Actions (optional)
    var onViewDetails: (() -> Void)?
    var onCopyName: (() -> Void)?
    var onDelete: (() -> Void)?
    #if os(macOS)
    var onOpenInNewWindow: (() -> Void)?
    #endif

    init(
        lesson: CDLesson,
        secondaryTextStyle: SecondaryTextStyle = .section,
        showTagIcon: Bool = false,
        onViewDetails: (() -> Void)? = nil,
        onCopyName: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.lesson = lesson
        self.secondaryTextStyle = secondaryTextStyle
        self.showTagIcon = showTagIcon
        self.onViewDetails = onViewDetails
        self.onCopyName = onCopyName
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(secondaryTextStyle == .areaAndSequence ? 1 : nil)
                
                Group {
                    switch secondaryTextStyle {
                    case .areaAndSequence:
                        Text("\(lesson.area) · \(lesson.sequence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    case .section:
                        if !lesson.section.isEmpty {
                            Text(lesson.section)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            if showTagIcon {
                // Structural affordance only (no student tracking)
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.45))
            }
        }
        .padding(.vertical, secondaryTextStyle == .areaAndSequence ? 6 : 2)
        .contentShape(Rectangle())
        .hoverableRow()
        .contextMenu {
            if let onViewDetails {
                Button {
                    onViewDetails()
                } label: {
                    Label("View Details", systemImage: "doc.text")
                }
            }

            #if os(macOS)
            Button {
                if let onOpenInNewWindow {
                    onOpenInNewWindow()
                } else {
                    if let id = lesson.id { openLessonInNewWindow(id) }
                }
            } label: {
                Label("Open in New Window", systemImage: "uiwindow.split.2x1")
            }
            #endif

            Divider()

            Button {
                if let onCopyName {
                    onCopyName()
                } else {
                    copyLessonName()
                }
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }

            Button {
                copyLessonInfo()
            } label: {
                Label("Copy Area & Group", systemImage: "doc.on.clipboard")
            }

            if let onDelete {
                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func copyLessonName() {
        let name = lesson.name.isEmpty ? "Untitled Lesson" : lesson.name
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        #else
        UIPasteboard.general.string = name
        #endif
    }

    private func copyLessonInfo() {
        let info = "\(lesson.area) · \(lesson.sequence)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        #else
        UIPasteboard.general.string = info
        #endif
    }
}
