import AppIntents
import SwiftUI

// MARK: - Intelligence Pane

/// Settings › Intelligence: Apple Intelligence (with the Private Cloud choice
/// when this build may use it), lesson planning, Siri, the connections to
/// Calendar, Reminders and Tide, and on the Mac Claude Desktop; debug builds
/// add a Developer card.
struct SettingsIntelligencePane: View {
    @AppStorage(UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
    private var allowAutomaticPrivateCloud = false

    var body: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.appleIntelligence) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    appleIntelligenceStatus
                    if showsPrivateCloud {
                        Divider()
                        privateCloudToggle
                    }
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

            SettingsGroup(.appleCalendar, collapsible: true) {
                CalendarSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.reminders, collapsible: true) {
                ReminderSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.tide, collapsible: true) {
                TideSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }

            #if os(macOS)
            SettingsGroup(.claudeDesktop) {
                ClaudeDesktopSettingsView()
                    .frame(maxWidth: .infinity)
            }
            #endif

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

    // MARK: - Private Cloud Compute

    /// Only a build with the Private Cloud entitlement can use it, so only
    /// that build offers the choice (today's builds don't).
    private var showsPrivateCloud: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        FoundationModelClient.privateCloudEntitled
        #else
        false
        #endif
    }

    /// The one AI choice in the app: whether a request the on-device model
    /// can't finish may move to Apple's Private Cloud Compute.
    private var privateCloudToggle: some View {
        Toggle(isOn: $allowAutomaticPrivateCloud) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text("Allow Private Cloud Compute")
                Text(
                    "When on, a request too big for this device can finish on Apple's servers, "
                        + "which don't keep your data. When off, student records never leave this "
                        + "device, and anything Apple Intelligence on this device can't finish just stops."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    private let onDevice = FoundationModelClient(kind: .onDevice)
    private let privateCloud = FoundationModelClient(kind: .privateCloud)

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            statusLine(
                label: "On this device",
                available: onDevice.isAvailable,
                reason: onDevice.unavailabilityReason
            )
            if FoundationModelClient.privateCloudEntitled {
                Divider()
                statusLine(
                    label: "Private Cloud Compute",
                    available: privateCloud.isAvailable,
                    reason: privateCloud.unavailabilityReason
                )
            }
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
