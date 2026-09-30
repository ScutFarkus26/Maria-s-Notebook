import SwiftUI

/// A consistent header component used across all main views in the app.
/// Provides a large title with optional trailing content (pickers, buttons, etc.)
struct ViewHeader<TrailingContent: View>: View {
    let title: String
    @ViewBuilder let trailingContent: () -> TrailingContent

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Set inside the More tab's stack, whose bar holds the back button even at
    /// the iPad mini's regular width, so the bar is never hidden there.
    @Environment(\.navigationPush) private var enclosingPush
    #endif

    init(title: String, @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() }) {
        self.title = title
        self.trailingContent = trailingContent
    }

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact || enclosingPush != nil {
            compactHeader
        } else {
            regularHeader
        }
        #else
        regularHeader
        #endif
    }

    private var regularHeader: some View {
        // Title and controls share a line when they fit at their natural
        // widths; when they don't, squeezing them hyphenated the title
        // ("Proce-dures") and stood button labels on end, so the controls drop
        // to their own row, which scrolls if it is still too wide.
        ViewThatFits(in: .horizontal) {
            HStack {
                titleText
                Spacer()
                trailingContent()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                titleText
                controlsRow
            }
        }
        .padding()
        .backgroundPlatform()
        // Hide the parent navigation bar since ViewHeader provides its own title.
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    #if os(iOS)
    /// On a phone the page sits in a navigation stack whose bar keeps the back
    /// button, so the title goes to that bar and only the controls stay here —
    /// drawing it here too showed every title twice.
    @ViewBuilder
    private var compactHeader: some View {
        if TrailingContent.self == EmptyView.self {
            Color.clear
                .frame(height: 0)
                .navigationTitle(title)
        } else {
            controlsRow
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .backgroundPlatform()
                .navigationTitle(title)
        }
    }
    #endif

    private var controlsRow: some View {
        ScrollView(.horizontal) {
            HStack {
                trailingContent()
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var titleText: some View {
        Text(title)
            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ViewHeaderPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Today")
            Divider()
            Spacer()
        }
    }
}

#Preview("Simple Header") {
    ViewHeaderPreview()
}

private struct ViewHeaderPreview2: View {
    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Checklist") {
                Picker("Area", selection: .constant("Biology")) {
                    Text("Biology").tag("Biology")
                    Text("Math").tag("Math")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            Divider()
            Spacer()
        }
    }
}

#Preview("Header with Controls") {
    ViewHeaderPreview2()
}
