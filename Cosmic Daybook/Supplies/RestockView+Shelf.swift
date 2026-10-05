// RestockView+Shelf.swift
// The shelf: staples grouped by where they live ("No place yet" last), an
// Add a Staple tile, and chips for common staples not on it yet.

import SwiftUI
import CoreData

extension RestockView {

    /// Staples most classrooms keep, offered as one-click chips until added.
    static let commonStaples = [
        "Tissues", "Hand soap", "Paper towels", "Toilet paper", "Glue sticks", "Pencils",
        "Dry-erase markers", "Copy paper"
    ]

    var shelfSection: some View {
        let groups = RestockService.shelf(staples)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeading("The shelf", detail: shelfHint)
                .padding(.top, 6)
            if groups.isEmpty {
                Text("Put the things the classroom always needs here. When one runs low, click it, "
                     + "and it goes on the office run or the to-order list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Label(group.title, systemImage: "mappin")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 10) {
                        ForEach(group.staples, id: \.objectID) { staple in
                            tile(staple)
                        }
                    }
                }
            }
            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 10) {
                addStapleTile
            }
            commonStapleChips
        }
    }

    private var shelfHint: String {
        #if os(macOS)
        "Click a tile when something runs low · right-click for more"
        #else
        "Tap a tile when something runs low · touch and hold for more"
        #endif
    }

    private var tileColumns: [GridItem] {
        isCompact
            ? [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            : [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 10)]
    }

    private func tile(_ staple: CDSupply) -> some View {
        RestockTile(
            supply: staple,
            byLine: byLine(for: staple),
            onSetLevel: { setLevel(staple, to: $0) },
            onEdit: { stapleSheet = .edit(staple) },
            onNote: {
                noteText = staple.notes
                noteStaple = staple
            },
            onHistory: { historyStaple = staple },
            onDelete: { deletingStaple = staple }
        )
    }

    private var addStapleTile: some View {
        Button {
            stapleSheet = .add(name: "")
        } label: {
            Label("Add a Staple", systemImage: "plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.vertical, 10)
                .overlay {
                    RoundedRectangle(cornerRadius: RestockStyle.tileRadius, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .contentShape(RoundedRectangle(cornerRadius: RestockStyle.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Add something the classroom always needs")
    }

    /// Common staples not on the shelf yet, matched whatever their case.
    var missingCommonStaples: [String] {
        let onShelf = Set(staples.map { $0.name.foldedKey() })
        return Self.commonStaples.filter { !onShelf.contains($0.foldedKey()) }
    }

    @ViewBuilder
    private var commonStapleChips: some View {
        let missing = missingCommonStaples
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Common staples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(missing, id: \.self) { name in
                        Button {
                            addCommonStaple(name)
                        } label: {
                            Label(name, systemImage: "plus")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Put \(name) on the shelf")
                    }
                }
            }
        }
    }

    // MARK: - Who and when

    /// "Ana · 8:12 AM" for a staple someone else marked Low or Out (the day
    /// instead of the time once it isn't today); "" for a stocked one or one
    /// you marked yourself.
    func byLine(for staple: CDSupply, now: Date = Date()) -> String {
        Self.byLine(
            isNeeded: staple.level.isNeeded,
            changedAt: staple.levelChangedAt,
            changedByID: staple.levelChangedByID,
            name: staple.levelChangedByName,
            viewer: author,
            now: now
        )
    }

    static func byLine(
        isNeeded: Bool,
        changedAt: Date?,
        changedByID: String?,
        name: String?,
        viewer: RestockAuthor,
        now: Date = Date()
    ) -> String {
        guard isNeeded, let when = changedAt,
              let who = someoneElse(changedByID: changedByID, name: name, viewer: viewer) else { return "" }
        let time = AppCalendar.shared.isDate(when, inSameDayAs: now)
            ? DateFormatters.shortTime.string(from: when)
            : DateFormatters.shortMonthDay.string(from: when)
        // It can start the line: "An assistant · 8:12 AM".
        return "\(who.prefix(1).uppercased())\(who.dropFirst()) · \(time)"
    }
}
