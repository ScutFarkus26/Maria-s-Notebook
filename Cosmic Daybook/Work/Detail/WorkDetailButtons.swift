import SwiftUI

// MARK: - Save Cancel Buttons

struct SaveCancelButtons: View {
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .surface(
                        UIConstants.CornerRadius.large,
                        fill: Color.primary.opacity(UIConstants.OpacityConstants.hint)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onSave()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Save")
                        .font(AppTheme.ScaledFont.bodySemibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .surface(UIConstants.CornerRadius.large, fill: Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Action Buttons

struct IconActionButton: View {
    let icon: String
    let color: Color
    let backgroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(backgroundColor))
        }
        .buttonStyle(.plain)
    }
}

struct RoundedActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .capsuleFill(color.opacity(UIConstants.OpacityConstants.medium))
        }
        .buttonStyle(.plain)
    }
}
