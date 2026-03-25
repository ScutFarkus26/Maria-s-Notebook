// SkeletonView.swift
// Shimmer loading placeholders that match final layout shapes

import SwiftUI

/// A shimmer effect modifier for skeleton loading states
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
            )
            .clipped()
            .onAppear {
                adaptiveWithAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Applies a shimmer animation for loading states
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// A single skeleton placeholder block
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 16
    var cornerRadius: CGFloat = UIConstants.CornerRadius.small

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(UIConstants.OpacityConstants.light))
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// A skeleton row mimicking a typical list row with avatar, title, and subtitle
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.light))
                .frame(width: 40, height: 40)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 140, height: 14)
                SkeletonBlock(width: 200, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// A skeleton card mimicking a stat or info card
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 80, height: 12)
            SkeletonBlock(height: 24)
            SkeletonBlock(width: 120, height: 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
    }
}

/// A loading view that shows skeleton rows, replacing ProgressView for lists
struct SkeletonListLoading: View {
    var rowCount: Int = 5

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<rowCount, id: \.self) { _ in
                SkeletonRow()
            }
        }
        .padding(.horizontal, 16)
    }
}
