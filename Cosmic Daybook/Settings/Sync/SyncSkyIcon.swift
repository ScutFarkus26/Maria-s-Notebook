import SwiftUI

// MARK: - Sync Sky Icon

/// Sync health drawn as a small patch of sky: sun when all is well, a drifting cloud
/// while syncing, a cloud over the sun when sync is slow, rain on an error, the moon
/// when offline, and a plain cloud while the app is still checking.
///
/// Size it with `.font(...)` like any symbol. Only the syncing cloud moves, and only
/// while it is on screen, the scene is not in the background, and Reduce Motion is off.
struct SyncSkyIcon: View {
    let health: CloudKitHealthCheck.SyncHealth

    var body: some View {
        styledSymbol
            .contentTransition(.symbolEffect(.replace))
            .modifier(SkyDriftModifier(active: health == .syncing))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(for: health))
    }

    @ViewBuilder
    private var styledSymbol: some View {
        let symbol = Image(systemName: Self.symbolName(for: health))
        switch health {
        case .healthy:
            symbol.symbolRenderingMode(.multicolor)
        case .syncing:
            symbol.symbolRenderingMode(.hierarchical).foregroundStyle(AppColors.info)
        case .warning:
            symbol.symbolRenderingMode(.palette).foregroundStyle(Color.secondary, Color.yellow)
        case .error:
            symbol.symbolRenderingMode(.palette).foregroundStyle(Color.secondary, AppColors.info)
        case .offline:
            symbol.symbolRenderingMode(.palette).foregroundStyle(Color.indigo, Color.secondary)
        case .unknown:
            symbol.symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
        }
    }

    static func symbolName(for health: CloudKitHealthCheck.SyncHealth) -> String {
        switch health {
        case .healthy: "sun.max.fill"
        case .syncing: "cloud.fill"
        case .warning: "cloud.sun.fill"
        case .error: "cloud.rain.fill"
        case .offline: "moon.zzz.fill"
        case .unknown: "cloud"
        }
    }

    static func accessibilityLabel(for health: CloudKitHealthCheck.SyncHealth) -> String {
        switch health {
        case .healthy: "Sync healthy"
        case .syncing: "Syncing"
        case .warning: "Sync is slow"
        case .error: "Sync needs attention"
        case .offline: "Offline, sync is paused"
        case .unknown: "Checking sync"
        }
    }
}

// MARK: - Drift

/// Lets the syncing cloud drift a couple of points side to side.
///
/// Like `spinning(while:)`, the moving view is its own branch: a `repeatForever` keyed
/// on a flag keeps SwiftUI redrawing every frame after the flag turns off, so the drift
/// ends by removing the branch (animation and all) whenever the cloud stops syncing,
/// scrolls or navigates out of view, the scene goes to the background, or Reduce Motion
/// is on.
private struct SkyDriftModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let active: Bool

    @State private var isOnScreen = false
    @State private var isScrolledIntoView = true

    private var drifting: Bool {
        active && !reduceMotion && isOnScreen && isScrolledIntoView && scenePhase != .background
    }

    func body(content: Content) -> some View {
        // A ZStack, not a Group: a Group would hand these lifecycle modifiers to each
        // branch, so swapping branches would fire them again and could flip `drifting` back.
        ZStack {
            if drifting {
                content.modifier(DriftingModifier())
            } else {
                content
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onScrollVisibilityChange(threshold: 0.01) { isScrolledIntoView = $0 }
    }
}

private struct DriftingModifier: ViewModifier {
    @State private var offset: CGFloat = -2

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    offset = 2
                }
            }
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SyncSkyIconPreview: View {
    private let states: [CloudKitHealthCheck.SyncHealth] = [
        .healthy, .syncing, .warning, .error("Preview"), .offline, .unknown
    ]

    var body: some View {
        HStack(spacing: AppTheme.Spacing.large) {
            ForEach(states.indices, id: \.self) { index in
                VStack(spacing: AppTheme.Spacing.small) {
                    SyncSkyIcon(health: states[index])
                        .font(.title)
                    Text(SyncSkyIcon.accessibilityLabel(for: states[index]))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

#Preview {
    SyncSkyIconPreview()
}
