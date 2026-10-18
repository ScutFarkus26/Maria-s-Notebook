// ScreenViewPicker.swift
// The switch between one screen's views: Meetings' Queue and History,
// Attendance's Roll and List, and each Lessons & Work half's live list and
// its History.
//
// These views used to be separate screens under Logs, which only repeated
// the screens they now live in (plan "Simplify the app", Phase 2). Apple's
// guidance for switching views inside a screen: on the Mac a segmented
// control, in the toolbar; noun labels; text or icons, never both. On iPhone
// and iPad the tabs picker (iOS 27), which VoiceOver reads as tabs. Search
// scopes are not a view switch: they filter results and show only while
// searching.

import SwiftUI

/// One screen's views, as a segmented control on the Mac and tabs elsewhere.
/// Where it sits (the toolbar, or a row above the content) is the screen's
/// choice.
struct ScreenViewPicker<Choice: Hashable & Identifiable>: View {
    /// What VoiceOver calls the control ("View").
    let title: String
    @Binding var selection: Choice
    let choices: [Choice]
    /// Each choice's noun ("Queue", "History").
    let label: (Choice) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices) { choice in
                Text(label(choice)).tag(choice)
            }
        }
        .labelsHidden()
        #if os(macOS)
        .pickerStyle(.segmented)
        .fixedSize()
        #else
        .pickerStyle(.tabs)
        #endif
    }
}
