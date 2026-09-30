#if os(iOS)
import SwiftUI

/// One VoiceOver element per tile: its label, the note as its value, a tap
/// that marks, and a Note action.
struct TileAccessibility: ViewModifier {
    let label: String
    let note: String
    let hint: String
    let onTap: () -> Void
    let onNote: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(note)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Note", onNote)
    }
}
#endif
