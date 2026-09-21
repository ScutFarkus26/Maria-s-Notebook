// LessonPopoverSearchField.swift
// The "find a lesson" field both add-a-lesson sheets use.
//
// Quick New Work and Add Lesson to Inbox ask the same question the same way —
// type to filter, tap to reopen the list, press Return on an exact name to take
// it — and had each written the field out. The candidate list underneath still
// belongs to the sheet: one of them also says what the child already has on
// record, and that is a real difference, so it is passed in.

import SwiftUI

struct LessonPopoverSearchField<Candidates: View>: View {
    @Binding private var text: String
    @Binding private var isShowingCandidates: Bool
    private var isFocused: FocusState<Bool>.Binding
    private let onSubmit: (String) -> Void
    private let candidates: () -> Candidates

    init(
        text: Binding<String>,
        isShowingCandidates: Binding<Bool>,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: @escaping (String) -> Void,
        @ViewBuilder candidates: @escaping () -> Candidates
    ) {
        self._text = text
        self._isShowingCandidates = isShowingCandidates
        self.isFocused = isFocused
        self.onSubmit = onSubmit
        self.candidates = candidates
    }

    var body: some View {
        TextField("Search lessons...", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused(isFocused)
            .onChange(of: text) { _, newValue in
                if !newValue.trimmed().isEmpty {
                    isShowingCandidates = true
                }
            }
            .onSubmit {
                // If user typed an exact lesson name, select it
                onSubmit(text.trimmed())
            }
            .onTapGesture {
                isShowingCandidates = true
            }
            .popover(isPresented: $isShowingCandidates, arrowEdge: .bottom) {
                candidates()
            }
    }
}
