// DayPadEditor.swift
// Plain-text scratchpad scoped to a single date. Auto-saves with a 500ms debounce.
// One CDDayPad row per day in the private store, CloudKit-synced.
//
// The editor can sit open for hours (the Mac's Today), so it never trusts the
// pad it loaded: every save looks the day's pad up again
// (`TodayDataFetcher.savePadText`), and a change to the day's pads from
// elsewhere (another device's edit or join, synced in) reloads the text,
// keeping anything she typed that isn't saved yet.

import SwiftUI
import CoreData

struct DayPadEditor: View {
    let day: Date

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    @State private var text: String = ""
    @State private var loadedForDay: Date?
    @State private var pad: CDDayPad?
    /// The pad's text as last loaded or saved here. A stored text that differs
    /// from it was changed elsewhere.
    @State private var baseText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(AppTheme.ScaledFont.callout)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: 120)
            .padding(.vertical, 4)
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !isFocused {
                    Text("Capture anything — fleeting thoughts, parent notes, things to remember by end of day.")
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .task(id: AppCalendar.startOfDay(day)) {
                loadPad(for: day)
            }
            .onChange(of: text) { _, newValue in
                scheduleSave(newValue)
            }
            .onDisappear {
                saveTask?.cancel()
                flushSave()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            ) { note in
                guard Self.touchesDayPads(note) else { return }
                // After the change is processed: reloading may join copies, which
                // changes the context again.
                Task { @MainActor in reloadIfChangedElsewhere() }
            }
    }

    /// Whether a context change inserted, updated, refreshed or deleted a pad.
    private static func touchesDayPads(_ note: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSRefreshedObjectsKey, NSDeletedObjectsKey]
        return keys.contains { key in
            (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is CDDayPad } ?? false
        }
    }

    /// Picks up the day's pad again after a change from elsewhere: a new text
    /// replaces hers when she has nothing unsaved; with unsaved typing, the
    /// next save adds it to the new text.
    private func reloadIfChangedElsewhere() {
        guard let loadedForDay else { return }
        let current = TodayDataFetcher.fetchDayPad(day: loadedForDay, context: viewContext)
        if viewContext.deletedObjects.contains(where: { $0 is CDDayPad }) {
            dependencies.saveCoordinator.save(viewContext, reason: "Join day pad copies")
        }
        pad = current
        let stored = current?.body ?? ""
        guard stored != baseText else { return }
        if text == baseText {
            baseText = stored
            text = stored
        } else {
            scheduleSave(text)
        }
    }

    private func loadPad(for day: Date) {
        let dayStart = AppCalendar.startOfDay(day)
        if loadedForDay == dayStart { return }
        flushSave()
        let existing = TodayDataFetcher.fetchDayPad(day: dayStart, context: viewContext)
        if viewContext.deletedObjects.contains(where: { $0 is CDDayPad }) {
            // Two devices' copies of the day were just joined into one.
            dependencies.saveCoordinator.save(viewContext, reason: "Join day pad copies")
        }
        pad = existing
        baseText = existing?.body ?? ""
        text = baseText
        loadedForDay = dayStart
    }

    private func scheduleSave(_ newValue: String) {
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                persist(newValue)
            } catch {
                // Cancelled — newer keystroke arrived
            }
        }
    }

    private func flushSave() {
        guard let loadedForDay else { return }
        if text == baseText && pad?.isDeleted != true { return }
        persist(text, dayOverride: loadedForDay)
    }

    private func persist(_ newValue: String, dayOverride: Date? = nil) {
        let dayStart = dayOverride ?? loadedForDay ?? AppCalendar.startOfDay(day)
        let saved = TodayDataFetcher.savePadText(newValue, base: baseText, day: dayStart, context: viewContext)
        pad = saved.pad
        baseText = saved.text
        if saved.text != newValue, dayOverride == nil {
            // Another device's text came in underneath; show the joined text.
            text = saved.text
        }
        dependencies.saveCoordinator.save(viewContext, reason: "Save day pad")
    }
}
