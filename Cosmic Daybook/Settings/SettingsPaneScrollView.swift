import SwiftUI

// MARK: - Settings Pane Scroll View

/// A settings pane's scroll view that jumps to one card and outlines it
/// briefly: the card a search matched. The jump happens when `focus` changes
/// (after a short pause, so typing settles and a pushed pane finishes sliding
/// in), and only once per card, so coming back to the pane doesn't jump again.
struct SettingsPaneScrollView<Content: View>: View {
    /// The `anchorID` of the card to show; nil when nothing is searched.
    let focus: String?
    @ViewBuilder var content: Content

    @State private var highlighted: String?
    @State private var jumpedTo: String?

    private static var settleDelay: Duration { .milliseconds(350) }
    private static var highlightDuration: Duration { .seconds(1.5) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .environment(\.settingsHighlightedAnchor, highlighted)
            .task(id: focus) {
                await jump(to: focus, with: proxy)
            }
        }
    }

    private func jump(to focus: String?, with proxy: ScrollViewProxy) async {
        guard let focus else {
            jumpedTo = nil
            highlighted = nil
            return
        }
        guard focus != jumpedTo else { return }
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled else { return }

        jumpedTo = focus
        adaptiveWithAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(focus, anchor: .top)
        }
        highlighted = focus

        try? await Task.sleep(for: Self.highlightDuration)
        guard !Task.isCancelled else {
            // Left the pane, or searched for something else: drop the outline now.
            if highlighted == focus { highlighted = nil }
            return
        }
        adaptiveWithAnimation(.easeOut(duration: 0.6)) {
            highlighted = nil
        }
    }
}
