import AppIntents
import SwiftUI

// MARK: - Intelligence Pane

/// Settings › Intelligence: Apple Intelligence (with the Private Cloud choice),
/// lesson planning, and Siri; debug builds add a Developer card.
struct SettingsIntelligencePane: View {
    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.appleIntelligence) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    appleIntelligenceStatus
                    Divider()
                    PrivateCloudSettingsView()
                }
                .frame(maxWidth: .infinity)
            }

            SettingsGroup(.lessonPlanning) {
                LessonPlanningSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.siri, footer: siriFooter) {
                siriShortcutsTips
            }

            #if DEBUG
            // Not teacher settings: release builds use AIConfigurationResolver's defaults.
            SettingsGroup(title: "Developer", systemImage: "hammer.fill", collapsible: true) {
                VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                    LessonPlanningDeveloperSettingsView()
                    Divider()
                    AIConnectionTestView()
                }
                .frame(maxWidth: .infinity)
            }
            #endif
        }
    }

    // MARK: - Apple Intelligence Status

    @ViewBuilder
    private var appleIntelligenceStatus: some View {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        AppleIntelligenceStatusRow()
        #else
        appleIntelligenceUnavailableView
        #endif
    }

    private var appleIntelligenceUnavailableView: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text("Not available")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(AppColors.warning)
                Text("Requires Apple Intelligence to be turned on")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Siri & Shortcuts Tips

    private var siriFooter: String {
        #if os(macOS) || targetEnvironment(macCatalyst)
        "Try these with Siri, ending each with \"in Cosmic Daybook\", or find them in the Shortcuts app. "
            + "No setup needed."
        #else
        "Try these with Siri, or find them in the Shortcuts app. No setup needed."
        #endif
    }

    /// The shipped App Shortcuts (`CosmicDaybookAppShortcuts`) worth teaching:
    /// attendance, observations and presentations.
    private var siriShortcutsTips: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS) || targetEnvironment(macCatalyst)
            // SiriTipView is unavailable on macOS and Mac Catalyst; list the phrases as text instead.
            VStack(alignment: .leading, spacing: AppTheme.Spacing.verySmall) {
                Label("\"Mark [student] here\"", systemImage: "mic")
                Label("\"Mark [student] late\"", systemImage: "mic")
                Label("\"Mark [student] absent\"", systemImage: "mic")
                Label("\"Undo attendance\"", systemImage: "mic")
                Label("\"Log an observation about [student]\"", systemImage: "mic")
                Label("\"Mark [lesson] as presented\"", systemImage: "mic")
            }
            .font(.callout)
            .foregroundStyle(.primary)
            #else
            SiriTipView(intent: MarkHereIntent())
            SiriTipView(intent: MarkLateIntent())
            SiriTipView(intent: MarkAbsentIntent())
            SiriTipView(intent: UndoAttendanceIntent())
            SiriTipView(intent: LogObservationIntent())
            SiriTipView(intent: MarkLessonPresentedIntent())
            #endif
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Apple Intelligence Status Row

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

struct AppleIntelligenceStatusRow: View {
    private let onDevice = LocalModelClient()
    private let privateCloud = PrivateCloudModelClient()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            statusLine(
                label: "On this device",
                available: onDevice.isAvailable,
                reason: onDevice.unavailabilityReason
            )
            Divider()
            statusLine(
                label: "Private Cloud Compute",
                available: privateCloud.isAvailable,
                reason: privateCloud.unavailabilityReason
            )
        }
    }

    private func statusLine(label: String, available: Bool, reason: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? AppColors.success : AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text("\(label): \(available ? "Ready" : "Not available")")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(available ? AppColors.success : AppColors.warning)

                if !available {
                    Text(reason)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
#endif
