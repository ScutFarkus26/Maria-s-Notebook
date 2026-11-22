// PlatformTypes.swift
// One name for the color class on each platform, for code that draws with
// UIKit on iPhone and iPad and AppKit on the Mac (album highlight colors).
// It lived in the parent report generator until that was taken out
// (2026-11-21).

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif
