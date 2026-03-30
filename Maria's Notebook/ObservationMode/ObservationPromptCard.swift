// ObservationPromptCard.swift
// Rotating prompt card showing a Montessori observation question.

import SwiftUI

struct ObservationPromptCard: View {
    let prompt: ObservationPrompt
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Previous button
            Button {
                onPrevious()
            } label: {
                Image(systemName: SFSymbol.Navigation.chevronLeft)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Prompt content
            VStack(spacing: 6) {
                Text(prompt.category.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text(prompt.question)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // Next button
            Button {
                onNext()
            } label: {
                Image(systemName: SFSymbol.Navigation.chevronRight)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CardStyle.cornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
        )
    }
}
