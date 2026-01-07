// LessonsListView.swift
// Performance-optimized List view for lessons with reordering support.
// Reordering is only enabled when onReorder is provided (manual mode + group selected).
// Uses native List.onMove for lightweight, reliable reordering without expensive animations.

import SwiftUI

struct LessonsListView: View {
    let lessons: [Lesson]
    let onTapLesson: (Lesson) -> Void
    let onReorder: ((_ movingLesson: Lesson, _ fromIndex: Int, _ toIndex: Int, _ subset: [Lesson]) -> Void)?
    let onGiveLesson: ((Lesson) -> Void)?
    let statusCounts: [UUID: Int]?
    
    var body: some View {
        List {
            ForEach(lessons, id: \.id) { lesson in
                LessonListRow(
                    lesson: lesson,
                    statusCount: statusCounts?[lesson.id]
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapLesson(lesson)
                }
                #if os(macOS)
                .overlay(RightClickCatcher(onRightClick: { onGiveLesson?(lesson) }))
                #else
                .contextMenu {
                    Button {
                        onGiveLesson?(lesson)
                    } label: {
                        Label("Give Lesson", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                #endif
            }
            .onMove(perform: onReorder != nil ? { source, destination in
                guard let onReorder = onReorder else { return }
                guard let fromIndex = source.first else { return }
                let toIndex = destination > fromIndex ? destination - 1 : destination
                guard fromIndex < lessons.count && toIndex < lessons.count else { return }
                let movingLesson = lessons[fromIndex]
                onReorder(movingLesson, fromIndex, toIndex, lessons)
            } : nil)
        }
        .listStyle(.plain)
    }
}

private struct LessonListRow: View {
    let lesson: Lesson
    let statusCount: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(lesson.name.isEmpty ? "Untitled Lesson" : lesson.name)
                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Spacer()
                    if lesson.source == .personal {
                        Text(lesson.personalKind?.badgeLabel ?? "Personal")
                            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !lesson.group.isEmpty || !lesson.subject.isEmpty {
                    Text(groupSubjectLine)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                if !lesson.subheading.isEmpty {
                    Text(lesson.subheading)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else if let firstLine = writeUpFirstLine {
                    Text(firstLine)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            if let count = statusCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.5)))
                    .accessibilityLabel("\(count) students need this")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
    
    private var groupSubjectLine: String {
        switch (lesson.subject.isEmpty, lesson.group.isEmpty) {
        case (false, false): return "\(lesson.subject) • \(lesson.group)"
        case (false, true): return lesson.subject
        case (true, false): return lesson.group
        default: return ""
        }
    }
    
    private var writeUpFirstLine: String? {
        let trimmed = lesson.writeUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: "\n").first.map(String.init)
    }
}

#if os(macOS)
import AppKit

private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

private class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let e = NSApp.currentEvent {
            if e.type == .rightMouseDown { return self }
            if e.type == .otherMouseDown && e.buttonNumber == 2 { return self }
            if e.type == .leftMouseDown && e.modifierFlags.contains(.control) { return self }
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onRightClick?() }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}
#endif

