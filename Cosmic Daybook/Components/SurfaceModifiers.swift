// SurfaceModifiers.swift
// The rounded and capsule surfaces the app hand-rolled hundreds of times,
// written once.
//
// Each modifier emits exactly the view tree the hand-rolled form did — the
// same shape, the same `style`, the same fill — so a migrated site renders
// pixel-for-pixel as before. `style` defaults to SwiftUI's own default
// (`.circular`), which is what a shape written without `style:` gets; a
// site that wrote `style: .continuous` passes it through unchanged.
//
// Only shapes that ten or more sites reproduce verbatim earn a modifier
// here. Anything else stays hand-rolled and uses the radius token alone
// (see Documentation/Implementation/design-system-migration.md).

import SwiftUI

extension View {
    /// `.background(RoundedRectangle(cornerRadius: radius, style: style).fill(fill))`
    func surface(
        _ radius: CGFloat,
        fill: some ShapeStyle,
        style: RoundedCornerStyle = .circular
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: style)
                .fill(fill)
        )
    }

    /// `.background(RoundedRectangle(…).fill(fill))`
    /// `.overlay(RoundedRectangle(…).stroke(stroke, lineWidth: lineWidth))`
    ///
    /// Both shapes share the radius and style, as every hand-rolled pair did.
    func surface(
        _ radius: CGFloat,
        fill: some ShapeStyle,
        stroke: some ShapeStyle,
        lineWidth: CGFloat = 1,
        style: RoundedCornerStyle = .circular
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: style)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: style)
                .stroke(stroke, lineWidth: lineWidth)
        )
    }

    /// `.background(Capsule(style: style).fill(fill))`
    func capsuleFill(
        _ fill: some ShapeStyle,
        style: RoundedCornerStyle = .circular
    ) -> some View {
        background(
            Capsule(style: style)
                .fill(fill)
        )
    }

    /// `.clipShape(RoundedRectangle(cornerRadius: radius, style: style))`
    func clipRounded(
        _ radius: CGFloat,
        style: RoundedCornerStyle = .circular
    ) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: style))
    }
}
