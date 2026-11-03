// RestockView+ShareBanner.swift
// The lead guide's banner for Restock records her assistant can't see yet:
// staples, needs or their history that belong in the classroom share and
// aren't in it. On the Mac its button only opens Settings › Classroom, where
// "Add them to the share" lives; on iPhone and iPad it says to do that on the
// Mac, the only place adding to the share runs (bug hunt 2026-11-02, #30).
// The page never shares anything itself (sharing already-shared records
// broke the Mac's export on 2026-09-28).

import SwiftUI
import CoreData

/// Restock records that belong in the classroom share and aren't in it.
nonisolated struct RestockShareGap: Equatable, Sendable {
    var staples = 0
    var needs = 0
    var history = 0

    init(staples: Int = 0, needs: Int = 0, history: Int = 0) {
        self.staples = staples
        self.needs = needs
        self.history = history
    }

    init(_ contents: ClassroomShareContents) {
        self.init(
            staples: contents.outside(of: "Supply"),
            needs: contents.outside(of: "OrderItem"),
            history: contents.outside(of: "SupplyTransaction")
        )
    }

    var isEmpty: Bool { staples == 0 && needs == 0 && history == 0 }

    /// "2 shelf items aren't shared with your assistant yet." Nil when
    /// everything is shared.
    var title: String? {
        guard !isEmpty else { return nil }
        var things: [String] = []
        if staples > 0 { things.append(Self.count(staples, "shelf item", "shelf items")) }
        if needs > 0 { things.append(Self.count(needs, "list item", "list items")) }
        guard !things.isEmpty else {
            return "Some shelf history isn't shared with your assistant yet."
        }
        let isOne = things.count == 1 && staples + needs == 1
        return "\(things.joined(separator: " and ")) \(isOne ? "isn't" : "aren't") shared with your assistant yet."
    }

    /// Where she adds them: Settings › Classroom on the Mac (#30).
    static var detail: String {
        #if os(macOS)
        "Your assistant can't see them. Add them to the share in Settings › Classroom."
        #else
        "Your assistant can't see them. Add them to the share on your Mac, in Settings › Classroom."
        #endif
    }

    private static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number.formatted()) \(number == 1 ? one : many)"
    }
}

extension RestockView {

    /// Shown to the lead guide while the classroom is shared and some of
    /// Restock isn't in the share.
    @ViewBuilder
    var shareBanner: some View {
        if let title = shareGap?.title {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.2.badge.gearshape")
                    .foregroundStyle(RestockStyle.lowText)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        shareBannerText(title)
                        Spacer(minLength: 0)
                        shareBannerButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        shareBannerText(title)
                        shareBannerButton
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(10, fill: RestockStyle.lowFill, stroke: RestockStyle.lowStroke.opacity(0.6), style: .continuous)
        }
    }

    private func shareBannerText(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(RestockShareGap.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// On the Mac only: Settings on iPhone and iPad can't add them (#30).
    @ViewBuilder
    private var shareBannerButton: some View {
        #if os(macOS)
        Button("Open Settings") { openClassroomSettings() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Settings › Classroom, where you can add them to the share")
        #endif
    }

    /// Reads which of Restock's records are missing from the share: once per
    /// visit to the page, never on a save. Only the lead guide owns the
    /// records, and only once the classroom is shared.
    func refreshShareGap() async {
        guard CDClassroomMembership.currentRole(in: viewContext) == .leadGuide,
              CDClassroomMembership.pinnedZoneName(in: viewContext) != nil else {
            shareGap = nil
            return
        }
        let sharing = dependencies.classroomSharingService
        if !sharing.isSharing { await sharing.refreshShareInBackground() }
        guard sharing.currentRole == .leadGuide, sharing.isSharing else {
            shareGap = nil
            return
        }
        let contents = await ClassroomSharingService.shareContents(
            coreDataStack: dependencies.coreDataStack,
            entities: ClassroomShareContents.restockEntityNames
        )
        shareGap = contents.map(RestockShareGap.init)
    }

    #if os(macOS)
    /// Settings › Classroom, in the Mac's Settings window.
    func openClassroomSettings() {
        UserDefaults.standard.set(
            SettingsCategory.classroom.rawValue, forKey: UserDefaultsKeys.settingsSelectedCategory
        )
        openSettings()
    }
    #endif
}
