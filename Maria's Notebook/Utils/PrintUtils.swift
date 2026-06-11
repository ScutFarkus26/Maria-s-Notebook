import SwiftUI

#if os(macOS)
import AppKit
import CoreGraphics
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif
