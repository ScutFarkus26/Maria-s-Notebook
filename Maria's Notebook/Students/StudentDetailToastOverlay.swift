// StudentDetailToastOverlay.swift
// Toast overlay component extracted from StudentDetailView

import SwiftUI

struct StudentDetailToastOverlay: View {
    let message: String?
    
    var body: some View {
        Group {
            if let message {
                Text(message)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
    }
}
