import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

extension DataManagementPanel {
    // MARK: - Restore Card

    var restoreCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Restore", systemImage: SFSymbol.Action.arrowCounterclockwise)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.warning)

                Picker("How to restore", selection: $viewModel.restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()

                // Both explained before the choice; the chosen one reads brighter.
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    restoreModeLine(
                        .merge,
                        "**Merge:** Add what's in the backup and keep everything else."
                    )
                    restoreModeLine(
                        .replace,
                        "**Replace:** Make this device match the backup exactly."
                    )
                }

                Button {
                    #if os(macOS)
                    presentMacFilePicker()
                    #else
                    showingImporter = true
                    #endif
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)

                Button {
                    Task { await viewModel.restoreMostRecentAutoBackup(viewContext: viewContext) }
                } label: {
                    Label("Restore last automatic backup", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
    }

    private func restoreModeLine(_ mode: BackupService.RestoreMode, _ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(viewModel.restoreMode == mode ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    #if os(macOS)
    private func presentMacFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [
            UTType(exportedAs: "com.cosmic-daybook.backup"),
            UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
            .data  // Fallback to allow selecting any file when macOS doesn't recognize custom UTType
        ]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    await viewModel.previewImportedURL(viewContext: viewContext, url: url)
                }
            }
        }
    }
    #endif
}
