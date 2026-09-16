//
//  ToolbarLayoutAssertionGuard.swift
//  Maria's Notebook
//
//  Keeps the Mac app alive through AppKit's "NSToolbarItemViewer's min/max
//  size is nan" assertion, and names the toolbar item that tripped it.
//

#if os(macOS)
import AppKit
import OSLog

/// The main thread's `NSAssertionHandler`, installed at app init.
///
/// AppKit raises `NSInternalInconsistencyException` from
/// `-[NSToolbarItemViewer minSize]` when an item viewer's cached size is NaN
/// mid-layout, and `+[NSApplication _crashOnException:]` then traps *without*
/// consulting `NSSetUncaughtExceptionHandler` — so the earlier uncaught-handler
/// diagnostics never ran. `NSAssert` does consult the current thread's
/// assertion handler first, and that hook runs *before* the exception exists.
///
/// For that one assertion this handler:
/// 1. logs the item identifier, window, sizes and a short stack (search the
///    unified log for `ToolbarNaN`),
/// 2. writes a sane size back into the viewer so the rest of the pass has a
///    number to lay out with, and
/// 3. returns without raising, which `minSize` treats as "carry on" — it re-reads
///    the (now repaired) size and returns it. The bar re-measures on the next
///    pass anyway.
///
/// Every other assertion is handed to the default handler unchanged, so the
/// behaviour elsewhere stays exactly AppKit's.
///
/// Verified in a scratch app on macOS 27.0: a poisoned viewer produced one
/// handled hit per pass, the layout completed, and AppKit recomputed the
/// viewer's size on the following pass. (The history of this crash lives in
/// the project memory under `album-toolbar-nan-crash`.)
nonisolated final class ToolbarLayoutAssertionGuard: NSAssertionHandler {

    private static let logger = Logger.app(category: "Toolbar")
    private static let failureSelector =
        NSSelectorFromString("handleFailureInMethod:object:file:lineNumber:description:")

    /// The fixed-argument prefix of AppKit's variadic handler.
    private typealias DefaultHandler =
        @convention(c) (AnyObject, Selector, Selector, AnyObject, NSString, Int, NSString?) -> Void

    private static let defaultHandler: DefaultHandler? =
        class_getMethodImplementation(NSAssertionHandler.self, failureSelector)
            .map { unsafeBitCast($0, to: DefaultHandler.self) }

    /// How many times the toolbar assertion has fired this launch.
    private(set) var hitCount = 0

    /// Installs the guard for the main thread — the only one that lays out
    /// toolbars, and the only one whose `NSAssert`s reach this handler.
    @MainActor
    static func install() {
        Thread.current.threadDictionary[NSAssertionHandlerKey] = ToolbarLayoutAssertionGuard()
        logger.notice("ToolbarLayoutAssertionGuard installed on the main thread")
    }

    // MARK: - NSAssert entry point

    /// Swift cannot override a C-variadic Objective-C method, but declaring the
    /// selector on the subclass has the runtime dispatch here all the same. The
    /// variadic tail is never read.
    @objc(handleFailureInMethod:object:file:lineNumber:description:)
    func handleFailure(method: Selector, object: AnyObject, file: String,
                       lineNumber: Int, description: String?) {
        if let description, description.contains("NSToolbarItemViewer's min/max size is nan"),
           let viewer = object as? NSView, Thread.isMainThread {
            hitCount += 1
            let hit = hitCount
            // Installed on the main thread only, and NSAssertionHandler is
            // per-thread, so this is the main actor.
            MainActor.assumeIsolated { Self.recover(viewer, method: method, hit: hit) }
            return
        }
        passThrough(method: method, object: object, file: file, lineNumber: lineNumber, description: description)
    }

    // MARK: - Recovery

    @MainActor
    private static func recover(_ viewer: NSView, method: Selector, hit: Int) {
        let item = item(of: viewer)
        let window = viewer.window
        let before = (size(of: viewer, ivar: "_minViewerSize"), size(of: viewer, ivar: "_maxViewerSize"))
        let repaired = repairSizes(of: viewer, item: item)
        let siblings = item?.toolbar?.items.map(\.itemIdentifier.rawValue).joined(separator: ",") ?? "?"

        let stack: String
        if hit <= 3 {
            stack = " stack=[" + Thread.callStackSymbols.dropFirst(2).prefix(18)
                .map { frameSummary($0) }.joined(separator: " < ") + "]"
        } else {
            stack = ""
        }
        logger.error("""
            ToolbarNaN hit=\(hit) in \(NSStringFromSelector(method)) \
            item='\(item?.itemIdentifier.rawValue ?? "?")' label='\(item?.label ?? "")' \
            window='\(window?.title ?? "")' toolbar=\(siblings) \
            min=\(describe(before.0)) max=\(describe(before.1)) \
            repaired=\(repaired.map(describe) ?? "none") frame=\(NSStringFromRect(viewer.frame)) \
            viewClass=\(item?.view.map { String(describing: type(of: $0)) } ?? "nil") \
            event=\(NSApp.currentEvent.map { String(describing: $0.type) } ?? "none")\(stack)
            """)
    }

    /// Writes the first usable size into the viewer's NaN'd caches and asks the
    /// toolbar view for a fresh pass. Returns the size written, if any.
    @MainActor
    private static func repairSizes(of viewer: NSView, item: NSToolbarItem?) -> NSSize? {
        let candidates: [NSSize?] = [
            size(of: viewer, ivar: "_maxViewerSize"),
            viewer.frame.size,
            item?.view?.fittingSize
        ]
        guard let good = candidates.first(where: { isUsable($0) }) ?? nil else { return nil }
        for ivar in ["_minViewerSize", "_maxViewerSize"] where !isUsable(size(of: viewer, ivar: ivar)) {
            setSize(good, of: viewer, ivar: ivar)
        }
        if let toolbarView = object(of: viewer, ivar: "_toolbarView") as? NSView {
            toolbarView.needsLayout = true
        }
        return good
    }

    private static func isUsable(_ size: NSSize?) -> Bool {
        guard let size else { return false }
        return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    // MARK: - Reading the private viewer

    /// `-[NSToolbarItemViewer item]` is a real accessor; KVC reaches it without
    /// naming the private class.
    private static func item(of viewer: NSView) -> NSToolbarItem? {
        guard viewer.responds(to: NSSelectorFromString("item")) else { return nil }
        return viewer.value(forKey: "item") as? NSToolbarItem
    }

    /// KVC into a named ivar, only when the runtime confirms the ivar exists —
    /// an unknown key would raise, and this runs inside a layout pass.
    private static func hasIvar(_ viewer: NSView, _ ivar: String) -> Bool {
        class_getInstanceVariable(type(of: viewer), ivar) != nil
    }

    private static func size(of viewer: NSView, ivar: String) -> NSSize? {
        guard hasIvar(viewer, ivar) else { return nil }
        return (viewer.value(forKey: ivar) as? NSValue)?.sizeValue
    }

    private static func setSize(_ size: NSSize, of viewer: NSView, ivar: String) {
        guard hasIvar(viewer, ivar) else { return }
        viewer.setValue(NSValue(size: size), forKey: ivar)
    }

    private static func object(of viewer: NSView, ivar: String) -> AnyObject? {
        guard hasIvar(viewer, ivar) else { return nil }
        return viewer.value(forKey: ivar) as AnyObject?
    }

    private static func describe(_ size: NSSize?) -> String {
        size.map { "\($0.width)x\($0.height)" } ?? "?"
    }

    /// "3   AppKit  0x… -[NSToolbarView layout] + 76" → "AppKit -[NSToolbarView layout]".
    private static func frameSummary(_ line: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return line }
        let symbol = parts.dropFirst(3).joined(separator: " ")
        let trimmed = symbol.range(of: " + ").map { String(symbol[..<$0.lowerBound]) } ?? symbol
        return "\(parts[1]) \(trimmed)"
    }

    // MARK: - Everything else

    /// Hands any other assertion to AppKit's own handler, which logs it and
    /// raises `NSInternalInconsistencyException` as usual. The variadic
    /// arguments cannot be forwarded from Swift, so format specifiers are
    /// escaped: the reason then shows the raw format string rather than
    /// reading garbage off the stack.
    private func passThrough(method: Selector, object: AnyObject,
                             file: String, lineNumber: Int, description: String?) {
        let literal = description?.replacingOccurrences(of: "%", with: "%%")
        if let defaultHandler = Self.defaultHandler {
            defaultHandler(self, Self.failureSelector, method, object, file as NSString,
                           lineNumber, literal as NSString?)
        } else {
            NSException(name: .internalInconsistencyException,
                        reason: description, userInfo: nil).raise()
        }
    }
}
#endif
