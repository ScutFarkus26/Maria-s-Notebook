import SwiftUI

/// Install models section with catalog rows and custom model pull for Ollama settings.
struct OllamaSettingsModelCatalogSection: View {
    let isConnected: Bool
    let availableModels: [OllamaModel]
    let isPulling: Bool
    let pullModelName: String
    let pullProgress: Double
    let pullStatusText: String
    let pullError: String?
    @Binding var showCustomModelField: Bool
    @Binding var customModelName: String
    let onPull: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Install Models")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)

            ForEach(OllamaModelCatalog.recommended) { model in
                catalogModelRow(model)
                if model.id != OllamaModelCatalog.recommended.last?.id {
                    Divider()
                }
            }

            if isConnected {
                Divider()
                customModelPullSection
            }
        }
    }

    // MARK: - Catalog Row

    @ViewBuilder
    private func catalogModelRow(_ model: OllamaModelCatalog) -> some View {
        let isInstalled = availableModels.contains { $0.name.hasPrefix(model.id) }
        let isCurrentlyPulling = isPulling && pullModelName == model.id
        let hasError = !isPulling && pullError != nil && pullModelName == model.id

        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            catalogModelInfoRow(model, isInstalled: isInstalled)

            if isCurrentlyPulling {
                pullProgressView
                    .padding(.top, AppTheme.Spacing.xsmall)
            }

            if hasError, let error = pullError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(2)
                    .padding(.top, AppTheme.Spacing.xsmall)
            }

            if !isInstalled && !isCurrentlyPulling {
                catalogInstallButton(modelID: model.id, hasError: hasError)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xsmall)
    }

    @ViewBuilder
    private func catalogModelInfoRow(_ model: OllamaModelCatalog, isInstalled: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Spacing.small) {
                    Text(model.name)
                        .font(AppTheme.ScaledFont.bodySemibold)

                    Text(model.parameterCount)
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Spacing.verySmall)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                        .clipShape(Capsule())

                    if isInstalled {
                        Text("Installed")
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
    }

    @ViewBuilder
    private func catalogInstallButton(modelID: String, hasError: Bool) -> some View {
        Button {
            onPull(modelID)
        } label: {
            Label(
                hasError ? "Retry" : "Install",
                systemImage: hasError ? "arrow.clockwise" : "arrow.down.circle"
            )
            .font(AppTheme.ScaledFont.captionSemibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(hasError ? AppColors.warning : .accentColor)
        .controlSize(.small)
        .disabled(isPulling)
        .padding(.top, AppTheme.Spacing.xsmall)
    }

    // MARK: - Custom Model Pull

    private var customModelPullSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Button {
                adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                    showCustomModelField.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: "plus.circle")
                    Text("Install Other Model")
                        .font(AppTheme.ScaledFont.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showCustomModelField ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showCustomModelField {
                HStack(spacing: AppTheme.Spacing.small) {
                    TextField("Model name (e.g. codellama:7b)", text: $customModelName)
                        .textFieldStyle(.plain)
                        .font(AppTheme.ScaledFont.body)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                        .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Button {
                        let name = customModelName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        onPull(name)
                    } label: {
                        if isPulling && pullModelName == customModelName.trimmingCharacters(in: .whitespaces) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Pull")
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isPulling || customModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if isPulling && pullModelName == customModelName.trimmingCharacters(in: .whitespaces) {
                    pullProgressView
                }
            }
        }
    }

    // MARK: - Shared Pull Progress

    private var pullProgressView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            ProgressView(value: pullProgress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack {
                Text(pullStatusText.isEmpty ? "Connecting..." : pullStatusText)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(pullProgress * 100))%")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
