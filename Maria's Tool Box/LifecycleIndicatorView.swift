import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LifecycleIndicatorView: View {
    let wasPresented: Bool
    let hasPending: Bool
    let isPlanned: Bool

    var body: some View {
        #if os(macOS)
        let tokenBackground = Color(nsColor: NSColor.windowBackgroundColor)
        #else
        let tokenBackground = Color(uiColor: UIColor.systemBackground)
        #endif
        Group {
            if wasPresented && !hasPending {
                Circle()
                    .fill(Color.accentColor)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            } else if isPlanned || (wasPresented && hasPending) {
                Circle()
                    .fill(tokenBackground)
                    .overlay(
                        Circle().stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            } else {
                Circle()
                    .fill(tokenBackground)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        LifecycleIndicatorView(wasPresented: true, hasPending: false, isPlanned: false)
        LifecycleIndicatorView(wasPresented: false, hasPending: true, isPlanned: true)
        LifecycleIndicatorView(wasPresented: false, hasPending: false, isPlanned: false)
    }
    .frame(height: 30)
    .padding()
}
