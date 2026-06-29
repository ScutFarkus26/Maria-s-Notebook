//  PlatformVerb.swift
//  Maria's Notebook
//
//  Platform-appropriate interaction verbs for user-facing copy.
//  macOS is pointer-driven ("Click"); iOS/iPadOS is touch ("Tap").
//  Use these instead of hardcoding "Tap" in strings that render on the Mac.

import Foundation

enum PlatformVerb {
    /// Capitalized primary interaction verb: "Click" on macOS, "Tap" on iOS.
    static var tap: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }

    /// Lowercased primary interaction verb, for mid-sentence use.
    static var tapLowercased: String {
        #if os(macOS)
        "click"
        #else
        "tap"
        #endif
    }

    /// SF Symbol for the primary interaction gesture.
    static var tapSymbol: String {
        #if os(macOS)
        "cursorarrow.click"
        #else
        "hand.tap"
        #endif
    }
}
