import SwiftUI

#if os(macOS)
import AppKit
#endif

extension DataManagementPanel {
    // MARK: - Storage Card

    var storageCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Storage", systemImage: SFSymbol.CDDocument.folderFill)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                    Spacer()
                    folderMenu
                }

                Text(viewModel.defaultFolderName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let date = viewModel.lastBackupDate {
                    Text("Last backup \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    let daysSince = AppCalendar.shared.dateComponents(
                        [.day], from: date, to: Date()
                    ).day ?? 0
                    if daysSince >= 7 {
                        Label(
                            "Backup is \(daysSince) days old",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                    }
                } else {
                    Label(
                        "No backup yet",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
                }
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            Button { showingFolderImporter = true } label: {
                Label("Choose another folder…", systemImage: SFSymbol.CDDocument.folderBadgePlus)
            }
            #if os(macOS)
            Button { openFolder() } label: {
                Label("Show in Finder", systemImage: "arrow.up.forward.square")
            }
            #endif
            if BackupDestination.resolveBookmarkedFolder() != nil {
                Divider()
                Button { resetToDefault() } label: {
                    Label("Reset to iCloud Drive", systemImage: "icloud")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Backup folder options")
    }

    #if os(macOS)
    private func openFolder() {
        if let url = BackupDestination.resolveDefaultFolder() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    #endif

    private func resetToDefault() {
        BackupDestination.clearDefaultFolder()
        viewModel.loadDefaultFolderName()
    }
}
