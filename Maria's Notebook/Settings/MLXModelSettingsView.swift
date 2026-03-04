import SwiftUI

/// Settings view for managing MLX local models — download, load, unload, and delete.
struct MLXModelSettingsView: View {
    @Environment(\.dependencies) private var dependencies
    @AppStorage(UserDefaultsKeys.mlxSelectedModel) private var selectedModelID = ""

    private var mlxManager: MLXModelManager {
        dependencies.aiRouter.mlxModelManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
            #if ENABLE_MLX_MODELS && canImport(MLXLLM)
            fullModelManagement
            #else
            unavailableMessage
            #endif
        }
    }

    // MARK: - Unavailable State

    private var unavailableMessage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("MLX models are not available in this build.")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)
            }

            Text("MLX requires Apple Silicon and the ENABLE_MLX_MODELS build flag.")
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Full Model Management (when MLX is available)

    #if ENABLE_MLX_MODELS && canImport(MLXLLM)
    private var fullModelManagement: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            ForEach(MLXModelInfo.recommended) { model in
                modelRow(model)
                if model.id != MLXModelInfo.recommended.last?.id {
                    Divider()
                }
            }

            Divider()

            infoFooter
        }
        .onAppear {
            mlxManager.refreshStatuses()
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: MLXModelInfo) -> some View {
        let status = mlxManager.modelStatuses[model.id] ?? .notDownloaded

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            // Header: name + size + status badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Text(model.name)
                            .font(AppTheme.ScaledFont.bodySemibold)

                        if case .loaded = status {
                            Text("Active")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(AppColors.success)
                                .padding(.horizontal, AppTheme.Spacing.verySmall)
                                .padding(.vertical, 1)
                                .background(AppColors.success.opacity(UIConstants.OpacityConstants.light))
                                .clipShape(Capsule())
                        }
                    }

                    Text(model.description)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Spacer()

                Text(String(format: "%.1f GB", model.sizeGB))
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }

            // Status-specific controls
            statusControls(for: model, status: status)
        }
        .padding(.vertical, AppTheme.Spacing.xsmall)
    }

    // MARK: - Status Controls

    @ViewBuilder
    private func statusControls(for model: MLXModelInfo, status: MLXModelStatus) -> some View {
        switch status {
        case .notDownloaded:
            Button {
                Task { try? await mlxManager.downloadModel(model) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(AppTheme.ScaledFont.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress):
            HStack(spacing: AppTheme.Spacing.small) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

        case .downloaded:
            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    Task {
                        try? await mlxManager.loadModel(model)
                        selectedModelID = model.id
                    }
                } label: {
                    Label("Load", systemImage: "play.circle")
                        .font(AppTheme.ScaledFont.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive) {
                    try? mlxManager.deleteModel(model)
                    if selectedModelID == model.id {
                        selectedModelID = ""
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(AppTheme.ScaledFont.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .loading:
            HStack(spacing: AppTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading into memory...")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

        case .loaded:
            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    mlxManager.unloadCurrentModel()
                } label: {
                    Label("Unload", systemImage: "stop.circle")
                        .font(AppTheme.ScaledFont.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    try? mlxManager.deleteModel(model)
                    if selectedModelID == model.id {
                        selectedModelID = ""
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(AppTheme.ScaledFont.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(message)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(2)

                Button {
                    Task { try? await mlxManager.downloadModel(model) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(AppTheme.ScaledFont.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Info Footer

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Models are stored locally (~2\u{2013}6 GB each).")
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.tertiary)
            Text("Only one model can be loaded in memory at a time.")
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.tertiary)
        }
    }
    #endif
}
