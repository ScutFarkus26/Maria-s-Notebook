// DayPadEditor.swift
// Plain-text scratchpad scoped to a single date. Auto-saves with a 500ms debounce.
// One CDDayPad row per day in the private store, CloudKit-synced.

import SwiftUI
import CoreData

struct DayPadEditor: View {
    let day: Date

    @Environment(\.managedObjectContext) private var viewContext

    @State private var text: String = ""
    @State private var loadedForDay: Date?
    @State private var pad: CDDayPad?
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
    }

    private func loadPad(for day: Date) {
        let dayStart = AppCalendar.startOfDay(day)
        if loadedForDay == dayStart { return }
        flushSave()
        let existing = TodayDataFetcher.fetchDayPad(day: dayStart, context: viewContext)
        pad = existing
        text = existing?.body ?? ""
        loadedForDay = dayStart
    }

    private func scheduleSave(_ newValue: String) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
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
        if pad?.body == text { return }
        if pad == nil && text.isEmpty { return }
        persist(text, dayOverride: loadedForDay)
    }

    private func persist(_ newValue: String, dayOverride: Date? = nil) {
        let dayStart = dayOverride ?? AppCalendar.startOfDay(day)
        if pad == nil {
            if newValue.isEmpty { return }
            pad = CDDayPad(context: viewContext, day: dayStart)
        }
        pad?.setBody(newValue)
        viewContext.safeSave()
    }
}
