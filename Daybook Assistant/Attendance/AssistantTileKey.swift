import SwiftUI

/// What the tiles mean, behind the Classroom sheet: each kind of tile drawn
/// small beside a line saying what it is. The glyphs come from the tile's
/// own code (`AttendanceTile.cornerGlyph`, `AttendanceBirthday.symbol`), so
/// the key can't drift from the grid.
struct AssistantTileKey: View {
    var body: some View {
        List {
            Section {
                entry(
                    .present, "Here",
                    "Marked in. During arrival a tap marks a child here, and a second tap takes it back."
                )
                entry(.unmarked, "Not marked yet", "Nobody has marked this child today.")
                entry(
                    .absent, "Absent",
                    "Closing arrival marks everyone not yet here absent. Hold a tile to mark absent with a reason."
                )
                entry(.tardy, "Late", "Came in after arrival closed. Counts as here.")
                entry(
                    .leftEarly, "Left early",
                    "Went home before the end of the day, so no longer counted as here. "
                        + "If they come back, hold the tile and choose Back in Class."
                )
            } header: {
                Text("Marks")
            } footer: {
                Text("Hold any tile for every mark, an absence reason, a note, and who marked it.")
            }

            Section("Extras") {
                entry(
                    .unmarked, corner: "hand.wave.fill", cornerColor: .teal, "Back after time away",
                    "Absent the last \(AttendanceWelcomeBack.threshold) or more school days, so give them "
                        + "a welcome at the door. Hold the tile to see how many days."
                )
                entry(
                    .unmarked, corner: AttendanceBirthday.birthday.symbol, cornerColor: .pink, party: true,
                    "Birthday", "It's their birthday today."
                )
                entry(
                    .unmarked, corner: AttendanceBirthday.halfBirthday.symbol, cornerColor: .pink, party: true,
                    "Half-birthday",
                    "A summer birthday, when school is out, is celebrated six months on instead."
                )
                entry(.present, note: true, "Note", "Someone left a note about the day. Hold the tile to read it.")
                entry(
                    .present, pickup: true, "Leaving early",
                    "Being picked up early today. Hold the tile to see when; mark Left Early when they go."
                )
            }

            Section("Around the grid") {
                row(
                    Image(systemName: "lock.fill").foregroundStyle(.secondary),
                    "Locked day",
                    "Beside the date: your guide has locked this day, so its marks can't be changed."
                )
                row(
                    Capsule().fill(Color.green).frame(width: 44, height: 4),
                    "Green line",
                    "Along the top of the bottom bar: how much of the class is here so far, "
                        + "and in purple, anyone who has left early."
                )
                row(
                    Label("Late", systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.lateAmber.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.lateAmber),
                    "Late button",
                    "In the bottom bar once arrival is closed: a tap now marks a child late. "
                        + "Tap the button to reopen arrival."
                )
            }
        }
        .navigationTitle("What the Tiles Mean")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func entry(
        _ status: AttendanceStatus,
        corner: String? = nil,
        cornerColor: Color = .primary,
        party: Bool = false,
        note: Bool = false,
        pickup: Bool = false,
        _ title: String,
        _ detail: String
    ) -> some View {
        row(
            AssistantKeyTile(
                status: status, corner: corner, cornerColor: cornerColor, party: party, note: note, pickup: pickup
            ),
            title,
            detail
        )
    }

    private func row(_ sample: some View, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            sample
                .frame(width: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A small tile drawn the way the grid draws one: solid green for here, an
/// outline for not marked, dashes for absent, and the corner glyph. The key
/// draws them, and so do onboarding's practice grid and symbols page.
struct AssistantKeyTile: View {
    let status: AttendanceStatus
    var name = "Maya"
    var height: CGFloat = 40
    var corner: String?
    var cornerColor: Color = .primary
    var party = false
    var note = false
    /// A pickup time set with Leaving Early….
    var pickup = false

    private var isHere: Bool { [.present, .tardy, .leftEarly].contains(status) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Text(name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isHere ? Color.black : status == .absent ? Color(.secondaryLabel) : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 9)
            .frame(height: height)
            .background {
                if isHere {
                    shape.fill(Color.green)
                } else if status == .unmarked {
                    shape.fill(Color(.tertiarySystemGroupedBackground))
                }
            }
            .overlay { border }
            .overlay(alignment: .topTrailing) {
                if let glyph = corner ?? AttendanceTile.cornerGlyph(for: status) {
                    Image(systemName: glyph)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isHere ? Color.black : cornerColor)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if note || pickup {
                    HStack(spacing: 3) {
                        if pickup { Image(systemName: "figure.walk.departure") }
                        if note { Image(systemName: "text.alignleft") }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .padding(5)
                }
            }
    }

    @ViewBuilder
    private var border: some View {
        if party {
            shape.strokeBorder(AttendanceTile.partyColors, lineWidth: 2)
        } else if status == .absent {
            shape.strokeBorder(Color(.secondaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if !isHere {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
}

#Preview {
    NavigationStack { AssistantTileKey() }
}
