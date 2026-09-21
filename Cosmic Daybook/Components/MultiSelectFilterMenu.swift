import SwiftUI

// MARK: - Selection Summary

/// The summary rule the filter chips share: the "all" title while nothing is
/// selected, the one selected item's own label when exactly one is, and
/// "N <plural>" otherwise.
struct FilterSelectionSummary {
    /// Title of the clear button inside the menu, and the chip's text while the
    /// selection is empty — e.g. "All Students".
    let allLabel: String
    /// Noun used for a multiple selection — e.g. "3 Students". Derived from
    /// `allLabel` unless a caller needs a different word.
    let pluralNoun: String

    init(allLabel: String, pluralNoun: String? = nil) {
        self.allLabel = allLabel
        if let pluralNoun {
            self.pluralNoun = pluralNoun
        } else if allLabel.hasPrefix("All ") {
            self.pluralNoun = String(allLabel.dropFirst(4))
        } else {
            self.pluralNoun = allLabel
        }
    }

    /// Resolves a single selection through `items`, exactly as the hand-rolled
    /// labels did: one selected id that no longer matches a visible item falls
    /// through to the count.
    func text<Item, ID: Hashable>(
        for selection: Set<ID>,
        items: [Item],
        id: (Item) -> ID?,
        label: (Item) -> String
    ) -> String {
        if selection.isEmpty { return allLabel }
        if selection.count == 1,
           let only = selection.first,
           let item = items.first(where: { id($0) == only }) {
            return label(item)
        }
        return "\(selection.count) \(pluralNoun)"
    }
}

// MARK: - Chip Label

/// The rounded chip the log filter bars use as their `Menu` label.
struct FilterMenuChipLabel: View {
    let systemImage: String
    let text: String
    /// Minimum hit height; the attendance log pins its chips to 44 pt.
    var minHeight: CGFloat?
    /// When true the chip takes the accent fill and foreground while
    /// `isSelected` — the treatment the age filter uses.
    var accentsSelection: Bool = false
    var isSelected: Bool = false

    @ViewBuilder
    private var chip: some View {
        let content = HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

        if let minHeight {
            content.frame(minHeight: minHeight)
        } else {
            content
        }
    }

    private func background(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
    }

    @ViewBuilder
    var body: some View {
        if accentsSelection {
            chip
                .background(background(
                    isSelected
                        ? Color.accentColor.opacity(UIConstants.OpacityConstants.medium)
                        : Color.primary.opacity(UIConstants.OpacityConstants.hint)
                ))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        } else {
            chip.background(background(Color.primary.opacity(UIConstants.OpacityConstants.hint)))
        }
    }
}

// MARK: - Multi-Select Menu

/// A filter menu that toggles items in and out of a `Set` of ids: an "all"
/// button that clears the selection, a divider, then one checkmarked button
/// per item.
struct MultiSelectFilterMenu<Item, ID: Hashable, MenuLabel: View>: View {
    private let items: [Item]
    @Binding private var selection: Set<ID>
    private let id: (Item) -> ID?
    private let label: (Item) -> String
    private let allLabel: String
    private let menuLabel: () -> MenuLabel

    init(
        items: [Item],
        selection: Binding<Set<ID>>,
        id: @escaping (Item) -> ID?,
        label: @escaping (Item) -> String,
        allLabel: String,
        @ViewBuilder menuLabel: @escaping () -> MenuLabel
    ) {
        self.items = items
        self._selection = selection
        self.id = id
        self.label = label
        self.allLabel = allLabel
        self.menuLabel = menuLabel
    }

    private struct Row: Identifiable {
        let id: ID
        let label: String
    }

    /// Items that carry an id, paired with their label. Items without one are
    /// skipped, as they were in each hand-rolled menu.
    private var rows: [Row] {
        items.compactMap { item in id(item).map { Row(id: $0, label: label(item)) } }
    }

    private func toggle(_ id: ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    var body: some View {
        Menu {
            Button(allLabel) { selection.removeAll() }
            Divider()
            ForEach(rows) { row in
                Button(action: { toggle(row.id) }, label: {
                    HStack {
                        if selection.contains(row.id) {
                            Image(systemName: "checkmark")
                        }
                        Text(row.label)
                    }
                })
            }
        } label: {
            menuLabel()
        }
    }
}

extension MultiSelectFilterMenu where MenuLabel == FilterMenuChipLabel {
    /// The chip-labelled form used by every filter bar.
    init(
        items: [Item],
        selection: Binding<Set<ID>>,
        id: @escaping (Item) -> ID?,
        label: @escaping (Item) -> String,
        summary: FilterSelectionSummary,
        systemImage: String,
        minHeight: CGFloat? = nil,
        accentsSelection: Bool = false
    ) {
        self.init(
            items: items,
            selection: selection,
            id: id,
            label: label,
            allLabel: summary.allLabel,
            menuLabel: {
                FilterMenuChipLabel(
                    systemImage: systemImage,
                    text: summary.text(for: selection.wrappedValue, items: items, id: id, label: label),
                    minHeight: minHeight,
                    accentsSelection: accentsSelection,
                    isSelected: !selection.wrappedValue.isEmpty
                )
            }
        )
    }
}

extension MultiSelectFilterMenu where MenuLabel == FilterMenuChipLabel, Item == ID {
    /// The chip-labelled form for items that are their own id (enums, strings).
    init(
        items: [Item],
        selection: Binding<Set<ID>>,
        label: @escaping (Item) -> String,
        summary: FilterSelectionSummary,
        systemImage: String,
        minHeight: CGFloat? = nil,
        accentsSelection: Bool = false
    ) {
        self.init(
            items: items,
            selection: selection,
            id: { $0 },
            label: label,
            summary: summary,
            systemImage: systemImage,
            minHeight: minHeight,
            accentsSelection: accentsSelection
        )
    }
}

// MARK: - Single-Select Menu

/// The single-select sibling: one checkmarked button per item, preceded by a
/// clear button when the filter is allowed to have no value.
struct SingleSelectFilterMenu<Item: Hashable>: View {
    private let items: [Item]
    @Binding private var selection: Item?
    private let label: (Item) -> String
    private let systemImage: String
    /// Title of the clear button — e.g. "All Types". Nil for filters that
    /// always carry a value, which then show no clear button.
    private let allLabel: String?
    private let minHeight: CGFloat?

    init(
        items: [Item],
        selection: Binding<Item?>,
        label: @escaping (Item) -> String,
        systemImage: String,
        allLabel: String? = nil,
        minHeight: CGFloat? = nil
    ) {
        self.items = items
        self._selection = selection
        self.label = label
        self.systemImage = systemImage
        self.allLabel = allLabel
        self.minHeight = minHeight
    }

    /// For filters that always have a value: writes through a non-optional
    /// binding, so the menu never offers a clear button.
    init(
        items: [Item],
        selection: Binding<Item>,
        label: @escaping (Item) -> String,
        systemImage: String,
        minHeight: CGFloat? = nil
    ) {
        self.init(
            items: items,
            selection: Binding(
                get: { selection.wrappedValue },
                set: { if let newValue = $0 { selection.wrappedValue = newValue } }
            ),
            label: label,
            systemImage: systemImage,
            allLabel: nil,
            minHeight: minHeight
        )
    }

    var body: some View {
        Menu {
            if let allLabel {
                Button(allLabel) { selection = nil }
                Divider()
            }
            ForEach(items, id: \.self) { item in
                Button(action: { selection = item }, label: {
                    HStack {
                        if selection == item {
                            Image(systemName: "checkmark")
                        }
                        Text(label(item))
                    }
                })
            }
        } label: {
            FilterMenuChipLabel(
                systemImage: systemImage,
                text: selection.map(label) ?? allLabel ?? "",
                minHeight: minHeight
            )
        }
    }
}
