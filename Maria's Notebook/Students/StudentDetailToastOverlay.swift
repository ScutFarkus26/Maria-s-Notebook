// StudentDetailToastOverlay.swift
// Toast overlay component extracted from StudentDetailView

import SwiftUI
import CoreData

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
                            .fill(Color.black.opacity(UIConstants.OpacityConstants.nearSolid))
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
    }
}
