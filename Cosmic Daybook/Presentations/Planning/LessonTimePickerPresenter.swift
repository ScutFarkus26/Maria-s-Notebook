// LessonTimePickerPresenter.swift
// The one way to show the lesson time picker, so the Scheduled cards and the
// lesson's sheet present it alike: a popover anchored to the view it is
// attached to on the Mac and iPad, and a half-height sheet with Done on the
// iPhone (docs/Plans/Plan - Lesson times on cards.md, decision 8).
//
// Attach it to the chip or row itself, not to a grid or list around it: the
// cards sit in a lazy container, and the popover needs a stable anchor.
//
//     .lessonTimePicker(item: $timeTarget) { target in
//         LessonTimePicker(lessonTitle: target.title, current: target.time, ...)
//     }

import SwiftUI

extension View {
    /// Shows `picker` for `item` while it is non-nil; closing it sets `item` back to nil.
    func lessonTimePicker<Item: Identifiable>(
        item: Binding<Item?>,
        arrowEdge: Edge? = nil,
        picker: @escaping (Item) -> LessonTimePicker
    ) -> some View {
        modifier(LessonTimePickerPresenter(item: item, arrowEdge: arrowEdge, picker: picker))
    }
}

private struct LessonTimePickerPresenter<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let arrowEdge: Edge?
    let picker: (Item) -> LessonTimePicker

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // Both presentations stay attached and each reads the item only when it is
    // the one in use, so the card under them never changes identity when the
    // window's width class changes.
    func body(content: Content) -> some View {
        content
            .popover(item: binding(whenSheet: false), arrowEdge: arrowEdge) { item in
                picker(item)
                    .frame(width: LessonTimePicker.popoverWidth)
            }
        #if os(iOS)
            .sheet(item: binding(whenSheet: true)) { item in
                LessonTimePickerSheet(picker: picker(item))
            }
        #endif
    }

    /// The iPhone, or an iPad window narrow enough that a popover would turn
    /// into a sheet anyway: a sheet with Done (Apple: avoid popovers on the iPhone).
    private var usesSheet: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private func binding(whenSheet sheet: Bool) -> Binding<Item?> {
        Binding(
            get: { usesSheet == sheet ? item : nil },
            set: { item = $0 }
        )
    }
}

#if os(iOS)
/// The iPhone's picker: half the screen, Done to close. The picker applies as
/// you go, so Done only closes.
private struct LessonTimePickerSheet: View {
    let picker: LessonTimePicker

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                picker
            }
            .navigationTitle("Start Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
