// StudentChip.swift
// The two student chips the app draws, written once each.
//
// `StudentChip` is the rounded, area-tinted chip: 16 pt continuous corners,
// footnote-semibold text, 10 × 6 padding, the area colour at 0.15. Before
// 2026-09-22 it was hand-rolled in PresentationCard, StudentPillsSection,
// PresentationDetailComponents and WorkCard+Compact, each with one extra:
// a "(Removed)" state, a record caption, a remove button, a leading icon.
// Those are the parameters here.
//
// `StudentCapsuleChip` is the small capsule chip a presentation pill shows
// per child: caption2-semibold text, 8 × 4 padding, the area colour at 0.15
// (0.06 while absent), with a red / amber / orange ring for absent /
// double-booked / not-yet-had. It was `ChipView` in Students/Selection and
// a private `StudentChipView` in WorkCard+Pill (the absent-only subset).

import SwiftUI

// MARK: - Rounded chip

struct StudentChip<Accessory: View>: View {
    /// What the text is drawn in.
    enum Foreground {
        /// The area colour — the chips on a presentation's detail and the
        /// participant chips on a compact work card.
        case tint
        /// The label colour, `.secondary` while `isMissing` — the read-only
        /// chips on a presentation card.
        case label
    }

    let label: String
    let tint: Color
    let isMissing: Bool
    let leadingSystemImage: String?
    let foreground: Foreground
    let onRemove: (() -> Void)?
    private let accessory: Accessory

    /// - Parameters:
    ///   - label: The child's short name, or "(Removed)".
    ///   - tint: The lesson area's colour.
    ///   - isMissing: The child no longer exists; the fill drops to the
    ///     faint label tint and, with `.label`, the text to `.secondary`.
    ///   - leadingSystemImage: A symbol drawn before the name in the chip's
    ///     own font.
    ///   - foreground: See `Foreground`.
    ///   - onRemove: Adds the `xmark.circle.fill` button after the accessory.
    ///   - accessory: Content between the name and the remove button, in
    ///     the inherited font (a `StudentRecordCaption`, for one).
    init(
        _ label: String,
        tint: Color,
        isMissing: Bool = false,
        leadingSystemImage: String? = nil,
        foreground: Foreground = .tint,
        onRemove: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self.tint = tint
        self.isMissing = isMissing
        self.leadingSystemImage = leadingSystemImage
        self.foreground = foreground
        self.onRemove = onRemove
        self.accessory = accessory()
    }

    private var fill: Color {
        isMissing
            ? Color.primary.opacity(UIConstants.OpacityConstants.faint)
            : tint.opacity(UIConstants.OpacityConstants.accent)
    }

    private var resolvedForeground: AnyShapeStyle {
        switch foreground {
        case .tint:
            return AnyShapeStyle(tint)
        case .label:
            return isMissing
                ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                : AnyShapeStyle(HierarchicalShapeStyle.primary)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            Text(label)
                .font(AppTheme.ScaledFont.captionSemibold)
            accessory
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .accessibilityLabel("Remove \(label)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(resolvedForeground)
        .surface(UIConstants.CornerRadius.extraLarge, fill: fill, style: .continuous)
    }
}

extension StudentChip where Accessory == EmptyView {
    init(
        _ label: String,
        tint: Color,
        isMissing: Bool = false,
        leadingSystemImage: String? = nil,
        foreground: Foreground = .tint,
        onRemove: (() -> Void)? = nil
    ) {
        self.init(
            label,
            tint: tint,
            isMissing: isMissing,
            leadingSystemImage: leadingSystemImage,
            foreground: foreground,
            onRemove: onRemove
        ) {
            EmptyView()
        }
    }
}

// MARK: - Capsule chip

struct StudentCapsuleChip: View {
    let label: String
    let tint: Color
    var isMissing = false
    var isAbsent = false
    var isDoubleBooked = false
    /// Orange ring: the child has not had this lesson yet.
    var isHighlighted = false
    /// Hourglass before the name; the chip becomes a button that calls
    /// `onTap` (a blocking work item the guide can open).
    var isWaiting = false
    var onTap: (() -> Void)?

    var body: some View {
        if isWaiting {
            Button {
                onTap?()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var fill: Color {
        isMissing
            ? Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
            : tint.opacity(isAbsent ? 0.06 : 0.15)
    }

    /// Priority: red (absent) > amber (scheduled more than once today)
    /// > orange (highlight) > clear.
    private var ring: Color {
        isAbsent ? Color.red
            : (isDoubleBooked ? AppColors.attention
                : (isHighlighted ? Color.orange : Color.clear))
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 4) {
            if isWaiting {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.warning)
            }
            Text(label)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
        }
        .foregroundStyle(isMissing || isAbsent ? .secondary : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .capsuleFill(fill)
        .overlay(
            Capsule().stroke(ring, lineWidth: 1)
        )
    }
}
