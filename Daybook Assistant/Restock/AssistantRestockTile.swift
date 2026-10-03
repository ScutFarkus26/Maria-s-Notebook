import SwiftUI

/// One staple on the shelf, in the attendance tile's grammar: the level shows
/// in the tile's shape (three bars, one, none; Out solid), not in color alone.
/// A tap goes Stocked → Low → Out; a tap on Out says "Hold for more". Holding
/// opens the menu: who set it and when, then We have plenty / Running low /
/// Out, Add a Note… and History.
struct AssistantRestockTile: View {
    let name: String
    let level: RestockLevel
    /// "You · 8:12 AM", for a Low or Out staple.
    let markedBy: String?
    let hasNote: Bool
    let menuHeader: String
    let onTap: () -> Bool
    let onSetLevel: (RestockLevel) -> Void
    let onNote: () -> Void
    let onHistory: () -> Void

    static let height: CGFloat = 92

    /// Set by a tap on Out, which does nothing: the tile says why.
    @State private var showsHoldHint = false
    @State private var holdHintTaps = 0
    @State private var taps = 0

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        card
            .contentShape(.contextMenuPreview, shape)
            .contentShape(shape)
            .onTapGesture(perform: tapped)
            .contextMenu { menu }
            .animation(.smooth(duration: 0.25), value: level)
            .animation(.smooth(duration: 0.2), value: showsHoldHint)
            .sensoryFeedback(.selection, trigger: taps)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: holdHintTaps)
            .task(id: holdHintTaps) {
                guard showsHoldHint, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
                showsHoldHint = false
            }
            .onChange(of: level) { showsHoldHint = false }
            .modifier(accessibility)
    }

    /// The name, the level's bars and word, and who set it.
    private var card: some View {
        let style = AssistantRestockStyle.level(level)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if hasNote {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(style.detail)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 7) {
                AssistantRestockBars(level: level)
                Text(level.displayName)
                    .font(.footnote.weight(.semibold))
            }
            Text(showsHoldHint ? "Hold for more" : (markedBy ?? " "))
                .font(.caption)
                .foregroundStyle(style.detail)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 3)
        }
        .foregroundStyle(style.text)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .topLeading)
        .background(style.fill, in: shape)
        .overlay {
            shape.strokeBorder(style.border, lineWidth: level == .stocked ? 1 : 1.5)
        }
    }

    private func tapped() {
        if onTap() {
            taps += 1
        } else {
            showsHoldHint = true
            holdHintTaps += 1
        }
    }

    private var accessibility: AssistantRestockTileAccessibility {
        AssistantRestockTileAccessibility(
            name: name, level: level, markedBy: markedBy, hasNote: hasNote,
            onTap: { _ = onTap() }, onSetLevel: onSetLevel, onNote: onNote, onHistory: onHistory
        )
    }

    @ViewBuilder
    private var menu: some View {
        Section {
            ForEach(RestockLevel.allCases) { choice in
                Button {
                    onSetLevel(choice)
                } label: {
                    Label(
                        Self.menuTitle(for: choice),
                        systemImage: choice == level ? "checkmark" : Self.icon(for: choice)
                    )
                }
            }
        } header: {
            Text(menuHeader)
        }
        Section {
            Button(hasNote ? "Edit Note…" : "Add a Note…", systemImage: "square.and.pencil", action: onNote)
            Button("History", systemImage: "clock", action: onHistory)
        }
    }

    static func menuTitle(for level: RestockLevel) -> String {
        switch level {
        case .stocked: "We have plenty"
        case .low: "Running low"
        case .out: "Out"
        }
    }

    private static func icon(for level: RestockLevel) -> String {
        switch level {
        case .stocked: "checkmark.circle"
        case .low: "battery.25"
        case .out: "battery.0"
        }
    }
}

/// The tile as one VoiceOver element: its name and level, who set it, a
/// double tap for the next level, and the hold menu's choices as actions.
struct AssistantRestockTileAccessibility: ViewModifier {
    let name: String
    let level: RestockLevel
    let markedBy: String?
    let hasNote: Bool
    let onTap: () -> Void
    let onSetLevel: (RestockLevel) -> Void
    let onNote: () -> Void
    let onHistory: () -> Void

    private var hint: String {
        level.afterTap.map { "Double tap to mark \($0.displayName.lowercased())" } ?? "Touch and hold for more"
    }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(name), \(level.displayName)"))
            .accessibilityValue(Text(verbatim: markedBy ?? ""))
            .accessibilityHint(Text(verbatim: hint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onTap() }
            .accessibilityActions { actions }
    }

    @ViewBuilder
    private var actions: some View {
        let others: [RestockLevel] = RestockLevel.allCases.filter { $0 != level }
        ForEach(others) { (choice: RestockLevel) in
            Button(AssistantRestockTile.menuTitle(for: choice)) { onSetLevel(choice) }
        }
        Button(hasNote ? "Edit Note" : "Add a Note", action: onNote)
        Button("History", action: onHistory)
    }
}
