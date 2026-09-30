import SwiftUI

// MARK: - Age Indicators Group

/// Look and feel › Age indicators: the lesson and work thresholds and colors,
/// with Reset to Defaults.
struct AgeIndicatorsSettingsGroup: View {
    @State private var isConfirmingReset = false

    var body: some View {
        SettingsGroup(.ageIndicators, collapsible: true, onReset: confirmReset) {
            VStack(spacing: AppTheme.Spacing.compact) {
                AgeIndicatorSettings(kind: .lesson)
                Divider()
                AgeIndicatorSettings(kind: .work)
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Reset the age indicators?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset to defaults", role: .destructive) {
                AgeIndicatorKind.lesson.resetToDefaults()
                AgeIndicatorKind.work.resetToDefaults()
            }
        } message: {
            Text("Both the lesson and work thresholds and colors go back to how they started.")
        }
    }

    private func confirmReset() {
        isConfirmingReset = true
    }
}

// MARK: - Age Indicator Kind

/// Which age indicator a block of settings edits: where it shows, the keys it
/// is stored under, and the values it starts with.
struct AgeIndicatorKind {
    let title: String
    let placement: String
    let keys: StudentAgeKeys
    let warningDays: Int
    let overdueDays: Int
    let freshColorHex: String
    let warningColorHex: String
    let overdueColorHex: String

    static let lesson = AgeIndicatorKind(
        title: "Lesson age",
        placement: "Shown for lessons in Planning › Agenda",
        keys: .lessons,
        warningDays: LessonAgeDefaults.warningDays,
        overdueDays: LessonAgeDefaults.overdueDays,
        freshColorHex: LessonAgeDefaults.freshColorHex,
        warningColorHex: LessonAgeDefaults.warningColorHex,
        overdueColorHex: LessonAgeDefaults.overdueColorHex
    )

    static let work = AgeIndicatorKind(
        title: "Work age",
        placement: "Shown for work in Planning › Work Agenda",
        keys: .work,
        warningDays: WorkAgeDefaults.warningDays,
        overdueDays: WorkAgeDefaults.overdueDays,
        freshColorHex: WorkAgeDefaults.freshColorHex,
        warningColorHex: WorkAgeDefaults.warningColorHex,
        overdueColorHex: WorkAgeDefaults.overdueColorHex
    )

    /// The ranges the steppers allow.
    static let warningRange = 0...30
    static let overdueRange = 1...60

    func resetToDefaults(in store: SyncedPreferencesStore = .shared) {
        store.set(warningDays, forKey: keys.warningDays)
        store.set(overdueDays, forKey: keys.overdueDays)
        store.set(freshColorHex, forKey: keys.freshColorHex)
        store.set(warningColorHex, forKey: keys.warningColorHex)
        store.set(overdueColorHex, forKey: keys.overdueColorHex)
    }
}

// MARK: - Age Indicator Settings

/// The thresholds and colors of one age indicator, with a preview of the pills they draw.
struct AgeIndicatorSettings: View {
    let kind: AgeIndicatorKind

    @SyncedAppStorage private var warningDays: Int
    @SyncedAppStorage private var overdueDays: Int
    @SyncedAppStorage private var freshHex: String
    @SyncedAppStorage private var warningHex: String
    @SyncedAppStorage private var overdueHex: String

    // The pickers hold a `Color`; the store holds hex. Each side follows the
    // other, so a change synced in from another device shows here too.
    @State private var freshColor: Color
    @State private var warningColor: Color
    @State private var overdueColor: Color

    init(kind: AgeIndicatorKind) {
        self.kind = kind
        let keys = kind.keys
        let fresh = SyncedAppStorage(wrappedValue: kind.freshColorHex, keys.freshColorHex)
        let warning = SyncedAppStorage(wrappedValue: kind.warningColorHex, keys.warningColorHex)
        let overdue = SyncedAppStorage(wrappedValue: kind.overdueColorHex, keys.overdueColorHex)
        _warningDays = SyncedAppStorage(wrappedValue: kind.warningDays, keys.warningDays)
        _overdueDays = SyncedAppStorage(wrappedValue: kind.overdueDays, keys.overdueDays)
        _freshHex = fresh
        _warningHex = warning
        _overdueHex = overdue
        _freshColor = State(initialValue: ColorUtils.color(from: fresh.wrappedValue))
        _warningColor = State(initialValue: ColorUtils.color(from: warning.wrappedValue))
        _overdueColor = State(initialValue: ColorUtils.color(from: overdue.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(kind.placement)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Warn after") {
                Stepper(value: $warningDays, in: AgeIndicatorKind.warningRange) {
                    Text(Self.schoolDays(warningDays))
                        .monospacedDigit()
                }
            }
            LabeledContent("Overdue after") {
                Stepper(value: $overdueDays, in: AgeIndicatorKind.overdueRange) {
                    Text(Self.schoolDays(overdueDays))
                        .monospacedDigit()
                }
            }

            colorRow("Fresh color", color: $freshColor)
            colorRow("Warning color", color: $warningColor)
            colorRow("Overdue color", color: $overdueColor)

            AgeIndicatorPreview(palette: palette)
        }
        .onChange(of: freshColor) { _, new in Self.store(new, in: &freshHex) }
        .onChange(of: warningColor) { _, new in Self.store(new, in: &warningHex) }
        .onChange(of: overdueColor) { _, new in Self.store(new, in: &overdueHex) }
        .onChange(of: freshHex) { _, new in Self.follow(new, into: &freshColor) }
        .onChange(of: warningHex) { _, new in Self.follow(new, into: &warningColor) }
        .onChange(of: overdueHex) { _, new in Self.follow(new, into: &overdueColor) }
    }

    private var palette: StudentAgePalette {
        StudentAgePalette(
            warningDays: warningDays,
            overdueDays: overdueDays,
            fresh: freshColor,
            warning: warningColor,
            overdue: overdueColor
        )
    }

    private func colorRow(_ title: String, color: Binding<Color>) -> some View {
        LabeledContent(title) {
            ColorPicker(title, selection: color)
                .labelsHidden()
        }
    }

    static func schoolDays(_ count: Int) -> String {
        count == 1 ? "1 school day" : "\(count) school days"
    }

    /// Writes a picked color, unless the store already holds it. A color just
    /// read from the stored hex is never written back, so a hex-to-color round
    /// trip can't nudge the value and echo it to the other devices.
    private static func store(_ color: Color, in hex: inout String) {
        guard color != ColorUtils.color(from: hex) else { return }
        let picked = ColorUtils.hexString(from: color)
        if picked != hex { hex = picked }
    }

    /// Takes up a stored color set elsewhere (another device, Reset to Defaults),
    /// unless the picker already shows it.
    private static func follow(_ hex: String, into color: inout Color) {
        if ColorUtils.hexString(from: color) != hex { color = ColorUtils.color(from: hex) }
    }
}

// MARK: - Preview Strip

/// Three sample pills, one per color, at ages the thresholds put in each band.
struct AgeIndicatorPreview: View {
    let palette: StudentAgePalette

    /// A fresh age halfway to the warning, the warning threshold, and the overdue threshold.
    /// Each pill takes the color that age really gets, so thresholds set out of
    /// order show that too.
    static func sampleDays(warningDays: Int, overdueDays: Int) -> [Int] {
        let warning = max(0, warningDays)
        return [warning / 2, warning, max(overdueDays, warning + 1)]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.small) { pills }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) { pills }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview")
    }

    private var pills: some View {
        let samples = Self.sampleDays(warningDays: palette.warningDays, overdueDays: palette.overdueDays)
        return ForEach(Array(samples.enumerated()), id: \.offset) { _, days in
            pill(days: days)
        }
    }

    private func pill(days: Int) -> some View {
        let color = palette.color(forDays: days)
        return HStack(spacing: AppTheme.Spacing.xsmall) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(days == 1 ? "1 day" : "\(days) days")
                .font(AppTheme.ScaledFont.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xsmall)
        .background(color.opacity(UIConstants.OpacityConstants.accent), in: Capsule())
        .overlay(Capsule().strokeBorder(color, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(AgeIndicatorSettings.schoolDays(days)): \(Self.statusName(palette.status(forDays: days)))"
        )
    }

    private static func statusName(_ status: LessonAgeStatus) -> String {
        switch status {
        case .fresh: return "fresh"
        case .warning: return "warning"
        case .overdue: return "overdue"
        }
    }
}
