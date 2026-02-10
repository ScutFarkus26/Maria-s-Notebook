// LessonPickerSection.swift
// Thin wrapper around the core Lesson picker UI, extracted for reuse.
// This view delegates to `LessonSection` (defined in the lesson picker components)
// and forwards a view model plus the computed display-title function.
//
// Notes:
// - Marked @MainActor to avoid cross-actor UI access warnings when used with SwiftData.
// - Keep this file tiny so the main picker components remain discoverable.

import SwiftUI
import SwiftData

/// A lightweight wrapper that renders the shared Lesson picker UI.
///
/// - Parameters:
///   - viewModel: The `LessonPickerViewModel` driving the selection and search.
///   - resolvedLesson: An optional resolved `Lesson` to display when the selection matches.
///   - isFocused: Binding used by the underlying picker to control first-responder focus.
@MainActor
struct LessonPickerSection: View {
    @Bindable var viewModel: LessonPickerViewModel
    let resolvedLesson: Lesson?
    @Binding var isFocused: Bool

    var body: some View {
        LessonSection(
            viewModel: viewModel,
            resolvedLesson: resolvedLesson,
            lessonDisplayTitle: viewModel.lessonDisplayTitle(for:),
            isFocused: $isFocused
        )
    }
}
