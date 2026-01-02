import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct InteractiveCard<Content: View>: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            Spacer(minLength: 0)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

#Preview {
    HStack(spacing: 16) {
        InteractiveCard(title: "Backup", systemImage: "icloud.and.arrow.up") {
            Text("Last backup: 2 hours ago")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        InteractiveCard(title: "Settings", systemImage: "gearshape", color: .blue) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configure your preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    .padding()
}

