import SwiftUI

public struct WhimsicalButton: View {
    public var title: String
    public var action: () -> Void

    @State private var isPressed: Bool = false
    #if os(macOS)
    @State private var isHovering: Bool = false
    #endif

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Whimsical gradient pill
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)

                // Subtle sparkles overlay
                sparklesOverlay
                    .opacity(0.16)
                    .blendMode(.plusLighter)

                // Title
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .frame(minWidth: 200)
            .scaleEffect(isPressed ? 0.97 : (hoverScale))
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isPressed)
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: hoverScale)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
        .accessibilityLabel(title)
    }

    private var gradientColors: [Color] {
        // Playful but clean palette
        [Color.pink, Color.orange, Color.purple]
    }

    private var hoverScale: CGFloat {
        #if os(macOS)
        return isHovering ? 1.02 : 1.0
        #else
        return 1.0
        #endif
    }

    private var sparklesOverlay: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<14, id: \.self) { _ in
                    Circle()
                        .fill([Color.white, .yellow, .mint, .cyan].randomElement()!.opacity(0.55))
                        .frame(width: CGFloat(Int.random(in: 3...6)), height: CGFloat(Int.random(in: 3...6)))
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .opacity(0.6)
                }
            }
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 20) {
        WhimsicalButton(title: "Open in Pages") { }
        WhimsicalButton(title: "Open Lesson Plan in Pages") { }
    }
    .padding()
}
