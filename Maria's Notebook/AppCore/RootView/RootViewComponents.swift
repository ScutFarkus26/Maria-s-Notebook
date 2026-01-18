// RootViewComponents.swift
// Supporting components for RootView - extracted for maintainability

import SwiftUI
import SwiftData

// MARK: - Quick Note Glass Button

/// Isolated component to prevent RootView re-renders during drag
struct QuickNoteGlassButton: View {
    @Binding var isShowingSheet: Bool

    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false

    @AppStorage("QuickNoteButton.offsetX") private var savedOffsetX: Double = 0
    @AppStorage("QuickNoteButton.offsetY") private var savedOffsetY: Double = 0

    var body: some View {
        visualContent
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .offset(offset)
            .padding(.trailing, 20)
            #if os(iOS)
            .padding(.bottom, 85)
            #else
            .padding(.bottom, 40)
            #endif
            .gesture(dragGesture)
            .onAppear {
                self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
            }
    }

    private var visualContent: some View {
        Group {
            #if os(iOS)
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            #else
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            #endif
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isPressed = true
                self.offset = CGSize(
                    width: savedOffsetX + value.translation.width,
                    height: savedOffsetY + value.translation.height
                )
            }
            .onEnded { value in
                isPressed = false
                let distance = hypot(value.translation.width, value.translation.height)

                if distance < 2 {
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    isShowingSheet = true
                } else {
                    let finalOffset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        self.offset = finalOffset
                    }
                }
            }
    }
}

// MARK: - Warning Banners

/// Warning banner displayed when using ephemeral/in-memory store.
struct EphemeralStoreWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    private var reason: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription)
        ?? "The persistent store could not be opened. Data will not persist this session."
    }

    private var isInMemoryMode: Bool {
        reason.contains("in-memory") || reason.contains("temporary")
    }

    private var warningTitle: String {
        isInMemoryMode ? "⚠️ SAFE MODE: CHANGES WILL NOT BE SAVED" : "Warning: Data won't persist this session"
    }

    private var warningMessage: String {
        isInMemoryMode
        ? "You are using an in-memory store. All data will be lost when you quit the app. Create a backup immediately!"
        : reason
    }

    private var iconColor: Color {
        isInMemoryMode ? .red : .yellow
    }

    private var titleColor: Color {
        isInMemoryMode ? .red : .primary
    }

    private var backgroundColor: AnyShapeStyle {
        isInMemoryMode ? AnyShapeStyle(Color.red.opacity(0.1)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        isInMemoryMode ? Color.red.opacity(0.3) : Color.primary.opacity(0.1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(titleColor)
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appRouter.requestCreateBackup()
            } label: {
                Label("Backup Now", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isInMemoryMode ? .red : nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(borderColor),
            alignment: .bottom
        )
    }
}

/// Warning banner displayed when CloudKit sync is enabled but not active.
struct CloudKitSyncWarningBanner: View {
    @Environment(\.appRouter) private var appRouter

    private var isiCloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var errorDescription: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    private var warningTitle: String {
        if !isiCloudSignedIn {
            return "⚠️ Not Signed Into iCloud"
        } else if let error = errorDescription, !error.isEmpty {
            return "⚠️ CloudKit Init Failed"
        } else {
            return "⚠️ iCloud Sync Issue"
        }
    }

    private var warningMessage: String {
        if !isiCloudSignedIn {
            return "Sign in to iCloud in System Settings to enable sync across devices."
        } else if let error = errorDescription, !error.isEmpty {
            return error
        } else {
            return "Sync is enabled but not currently active."
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isiCloudSignedIn ? "icloud.slash" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(.callout)
                    .fontWeight(.bold)
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                appRouter.navigateTo(.settings)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
    }
}
