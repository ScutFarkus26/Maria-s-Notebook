// RestockTile.swift
// One staple on the shelf. A click goes Stocked → Low → Out; a click on Out
// says where the rest is (the menu), as an attendance tile does when a tap
// does nothing. The menu has the three levels, Edit…, Add a Note…, History
// and Delete.

import SwiftUI
import CoreData

struct RestockTile: View {
    @ObservedObject var supply: CDSupply
    /// "Ana · 8:12" for a staple that's Low or Out; "" otherwise.
    let byLine: String
    let onSetLevel: (RestockLevel) -> Void
    let onEdit: () -> Void
    let onNote: () -> Void
    let onHistory: () -> Void
    let onDelete: () -> Void

    @State private var showsHint = false
    @State private var hintTaps = 0

    /// What a click on Out says.
    static var hint: String {
        #if os(macOS)
        "Right-click for more"
        #else
        "Touch and hold for more"
        #endif
    }

    private var level: RestockLevel { supply.level }

    var body: some View {
        Button(action: tap) { face }
            .buttonStyle(.plain)
            .contextMenu { menu }
            .animation(.smooth(duration: 0.2), value: level)
            .animation(.smooth(duration: 0.2), value: showsHint)
            .sensoryFeedback(.selection, trigger: level)
            .task(id: hintTaps) {
                guard showsHint, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
                showsHint = false
            }
            .onChange(of: level) { showsHint = false }
            .accessibilityLabel("\(supply.name), \(level.displayName)")
            .accessibilityHint(level.afterTap.map { "Marks it \($0.displayName)" } ?? "")
            .help(level.afterTap.map { "Mark \($0.displayName)" } ?? Self.hint)
    }

    /// The name, the level glyph and word, and who marked it (or the hint).
    private var face: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(supply.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            HStack(spacing: 7) {
                RestockLevelBars(level: level)
                Text(level.displayName)
                    .font(.caption.weight(.semibold))
            }
            Text(showsHint ? Self.hint : byLine)
                .font(.caption2)
                .foregroundStyle(detailStyle)
                .lineLimit(1)
                .frame(minHeight: 13, alignment: .leading)
                .padding(.top, 3)
        }
        .foregroundStyle(nameStyle)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(fill, in: shape)
        .overlay { shape.strokeBorder(stroke, lineWidth: level == .stocked ? 1 : 1.5) }
        .contentShape(shape)
    }

    private func tap() {
        if let next = level.afterTap {
            onSetLevel(next)
        } else {
            showsHint = true
            hintTaps += 1
        }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        ForEach(RestockLevel.allCases) { option in
            Button {
                onSetLevel(option)
            } label: {
                if option == level {
                    Label(option.menuTitle, systemImage: "checkmark")
                } else {
                    Text(option.menuTitle)
                }
            }
        }
        Divider()
        Button("Edit…", systemImage: "pencil", action: onEdit)
        Button(supply.notes.isEmpty ? "Add a Note…" : "Edit Note…", systemImage: "note.text", action: onNote)
        Button("History", systemImage: "clock.arrow.circlepath", action: onHistory)
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
    }

    // MARK: - Look

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RestockStyle.tileRadius, style: .continuous)
    }

    private var fill: Color {
        switch level {
        case .stocked: CardStyle.cardBackgroundColor
        case .low: RestockStyle.lowFill
        case .out: RestockStyle.outFill
        }
    }

    private var stroke: Color {
        switch level {
        case .stocked: Color.primary.opacity(0.15)
        case .low: RestockStyle.lowStroke
        case .out: RestockStyle.outFill
        }
    }

    private var nameStyle: Color {
        switch level {
        case .stocked: .primary
        case .low: RestockStyle.lowText
        case .out: .white
        }
    }

    private var detailStyle: Color {
        switch level {
        case .stocked: .secondary
        case .low: RestockStyle.lowText.opacity(0.85)
        case .out: RestockStyle.outDetail
        }
    }
}

nonisolated extension RestockLevel {
    /// The level as the tile's menu offers it.
    var menuTitle: String {
        switch self {
        case .stocked: "We Have Plenty"
        case .low: "Running Low"
        case .out: "Out"
        }
    }
}
