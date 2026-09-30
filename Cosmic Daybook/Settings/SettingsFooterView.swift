import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Settings Footer

/// The quiet line at the bottom of Settings: the app icon, name, version and build, and a
/// short Montessori phrase, picked afresh each time Settings opens.
///
/// Easter egg: tapping the icon five times in a row turns the "cosmic" accent on (a still
/// starfield here and behind the header, `CosmicHeaderAccent`); five more turn it off.
struct SettingsFooterView: View {
    @AppStorage(UserDefaultsKeys.settingsCosmicAccent) private var cosmicAccent = false
    @State private var quote = SettingsFooterView.quotes.randomElement() ?? "Follow the child."
    @State private var taps = CosmicTapCounter()

    /// Brief, widely known lines; one is shown each time Settings opens.
    static let quotes = [
        "Follow the child.",
        "Help me to do it myself.",
        "Play is the work of the child.",
        "Establishing lasting peace is the work of education.",
        "The hand is the instrument of the mind."
    ]

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xsmall) {
            SettingsFooterAppIcon()
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .onTapGesture(perform: registerTap)
                .accessibilityLabel(Self.appName)
                .accessibilityAction(named: cosmicAccent ? "Hide the stars" : "Show the stars", toggleCosmicAccent)
                .padding(.bottom, AppTheme.Spacing.xxsmall)
            Text(Self.appName)
                .font(.footnote.weight(.semibold))
            Text(Self.versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("“\(quote)”")
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.Spacing.xsmall)
            if cosmicAccent {
                Text("\(PlatformVerb.tap) the icon five times to put the stars away.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.large)
        .padding(.horizontal, AppTheme.Spacing.medium)
        .background {
            if cosmicAccent {
                CosmicStarfield()
                    .background(Color.indigo.opacity(UIConstants.OpacityConstants.hint))
                    .clipShape(RoundedRectangle(cornerRadius: SettingsStyle.cornerRadius, style: .continuous))
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: cosmicAccent)
    }

    private func registerTap() {
        if taps.register(at: Date()) {
            toggleCosmicAccent()
        }
    }

    private func toggleCosmicAccent() {
        adaptiveWithAnimation(.easeInOut(duration: 0.4)) {
            cosmicAccent.toggle()
        }
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Cosmic Daybook"
    }

    static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? "Version \(version)" : "Version \(version) (\(build))"
    }
}

// MARK: - Tap Counter

/// Counts taps on the footer icon. Five in a row, each within `window` of the last, is a
/// hit; a longer pause starts the count over. Compares timestamps, so no timer runs.
struct CosmicTapCounter {
    static let tapsNeeded = 5
    static let window: TimeInterval = 1.5

    private(set) var count = 0
    private var lastTap: Date?

    /// Records a tap; returns true on the tap that completes a run of five.
    mutating func register(at date: Date) -> Bool {
        if let lastTap, date.timeIntervalSince(lastTap) <= Self.window {
            count += 1
        } else {
            count = 1
        }
        lastTap = date
        guard count >= Self.tapsNeeded else { return false }
        count = 0
        self.lastTap = nil
        return true
    }
}

// MARK: - App Icon

/// The app's own icon where the platform hands it over (the Mac always does), else a
/// small stand-in tile in the icon's colors.
private struct SettingsFooterAppIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let icon = Self.icon {
            icon
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(tileGradient)
                .overlay {
                    Image(systemName: "book.closed.fill")
                        .font(.body)
                        .foregroundStyle(colorScheme == .dark ? Color.yellow : Color.indigo)
                }
        }
    }

    private var tileGradient: LinearGradient {
        // The icon's own backdrop: warm paper by day, deep violet at night.
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.17, green: 0.14, blue: 0.27), Color(red: 0.08, green: 0.06, blue: 0.13)]
            : [Color(red: 1.0, green: 0.97, blue: 0.89), Color(red: 0.94, green: 0.86, blue: 0.71)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private static let icon: Image? = {
        #if os(macOS)
        return Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let name = primary?["CFBundleIconName"] as? String ?? "AppIcon"
        return UIImage(named: name).map { Image(uiImage: $0) }
        #endif
    }()
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SettingsFooterViewPreview: View {
    var body: some View {
        SettingsFooterView()
            .frame(maxWidth: 420)
            .padding()
    }
}

#Preview {
    SettingsFooterViewPreview()
}
