// StudentCardHelpers.swift
// Shared utilities for student card components

import SwiftUI
import CoreData
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Symbol Support Cache

enum SymbolSupportCache {
    #if canImport(AppKit)
    static let hasStarFill: Bool = (NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) != nil)
    static let hasSparkles: Bool = (NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) != nil)
    static let hasBalloonFill: Bool = (NSImage(systemSymbolName: "balloon.fill", accessibilityDescription: nil) != nil)
    #elseif canImport(UIKit)
    static let hasStarFill: Bool = (UIImage(systemName: "star.fill") != nil)
    static let hasSparkles: Bool = (UIImage(systemName: "sparkles") != nil)
    static let hasBalloonFill: Bool = (UIImage(systemName: "balloon.fill") != nil)
    #else
    static let hasStarFill: Bool = true
    static let hasSparkles: Bool = true
    static let hasBalloonFill: Bool = true
    #endif
}

// MARK: - Color Extension

extension Color {
    static var cardBackground: Color {
        #if canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #elseif canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.white
        #endif
    }
}
