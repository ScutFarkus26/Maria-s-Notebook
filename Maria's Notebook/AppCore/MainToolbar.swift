// MainToolbar.swift
// Native macOS toolbar with action buttons for common operations.

import SwiftUI

#if os(macOS)
/// Provides toolbar content for the main window on macOS.
struct MainToolbar: ToolbarContent {
    @Environment(\.appRouter) private var appRouter

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    appRouter.requestNewLesson()
                } label: {
                    Label("New CDLesson", systemImage: "book.badge.plus")
                }

                Button {
                    appRouter.requestNewStudent()
                } label: {
                    Label("New CDStudent", systemImage: "person.badge.plus")
                }

                Button {
                    appRouter.requestNewWork()
                } label: {
                    Label("New Work", systemImage: "doc.badge.plus")
                }
            } label: {
                Label("New", systemImage: "plus")
            }
            .help("Create new lesson, student, or work")

            Button {
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search (Cmd+F)")
        }
    }
}
#endif
