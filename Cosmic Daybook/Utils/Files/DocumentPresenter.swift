// DocumentPresenter.swift
// Showing a stored file on iPhone and iPad: Quick Look to read it, the share
// sheet to hand it to another app.

#if os(iOS)
import QuickLook
import UIKit

/// Opens a file the app keeps (a story or packet PDF, a student file, a
/// lesson's Pages file or plan) on iPhone and iPad.
///
/// `UIApplication.open` with a `file://` URL isn't documented to open
/// anything, and on iOS it doesn't: Open PDF, a Student File card and Open in
/// Pages did nothing, and the failure went unseen. A file is shown with Quick
/// Look (`.preview`) or handed to another app through the share sheet
/// (`.share`, where Pages offers itself).
///
/// `open` waits for an iCloud file to come down first (up to a minute; after
/// a second it says so), and then (review of the 2026-10-17 fixes, a2 #8):
/// - one file at a time: a tap while another file is on its way or on screen
///   does nothing, so two taps no longer stack two sheets;
/// - nothing is shown when the tap's task was cancelled or the screen she
///   tapped on has closed during the wait;
/// - the sheet goes over the window she tapped in (the key window across all
///   scenes, not whichever scene came first on an iPad with two windows);
/// - security-scoped access to the file lasts from the tap until the sheet
///   closes, and also ends when the sheet goes away without saying so (its
///   screen closed under it): the next open finds it gone and lets go.
@MainActor
enum DocumentPresenter {
    enum Style {
        /// Quick Look, for reading.
        case preview
        /// The share sheet, for opening in another app, sending or saving.
        case share
    }

    /// How a request to show a file went.
    enum Outcome {
        case shown
        /// The file isn't on this device: moved, deleted, or not downloaded.
        case fileMissing
        /// There was no window to show it in.
        case notShown
        /// Another file is on its way or on screen; this tap was ignored.
        case busy
        /// She left the screen (or the tap was cancelled) while the file was
        /// on its way, so nothing was shown.
        case cancelled

        /// What to tell the guide, nil when there's nothing to say.
        var message: String? {
            switch self {
            case .shown, .busy, .cancelled: nil
            case .fileMissing: "Couldn't open the file. It may have been moved or deleted, "
                + "or it may still be downloading from iCloud. Try again in a moment."
            case .notShown: "Couldn't open the file. Try again."
            }
        }
    }

    /// The file being fetched or shown, and how to let go of it.
    private final class Opening {
        private var release: (() -> Void)?
        /// Set once the sheet is up; held weakly, so a sheet that went away
        /// without telling us is noticed.
        weak var controller: UIViewController?
        var isWaiting = true

        init(release: @escaping () -> Void) {
            self.release = release
        }

        /// Whether the sheet is still up (or still on its way up).
        var isShowing: Bool {
            guard let controller else { return false }
            return controller.viewIfLoaded?.window != nil || controller.isBeingPresented
        }

        /// Ends access to the file and frees the slot, once.
        func finish() {
            let done = release
            release = nil
            done?()
            if DocumentPresenter.current === self { DocumentPresenter.current = nil }
        }
    }

    private static var current: Opening?

    /// Whether a file is on its way or on screen.
    static var isBusy: Bool {
        guard let current else { return false }
        return current.isWaiting || current.isShowing
    }

    static let gettingFileMessage = "Getting the file from iCloud…"

    /// Shows `url` as `style` once it is on this device (`localURL` waits for
    /// an iCloud download; a seam for tests). See the type's notes for when
    /// nothing is shown.
    @discardableResult
    static func open(
        _ url: URL,
        as style: Style,
        waitingFor localURL: (URL) async -> URL = { await UbiquitousFile.localURL(for: $0) }
    ) async -> Outcome {
        // A sheet that closed without telling us lets go of its file now.
        if let current, !current.isWaiting, !current.isShowing { current.finish() }
        guard current == nil else { return .busy }

        let needsAccess = url.startAccessingSecurityScopedResource()
        let opening = Opening {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }
        current = opening
        let origin = tapOrigin()

        let notice = Task {
            try await Task.sleep(for: .seconds(1))
            ToastService.shared.showInfo(gettingFileMessage)
        }
        // A relative file URL is mishandled by some URL-based APIs on iOS 27.
        let file = await localURL(url).absoluteURL
        notice.cancel()
        opening.isWaiting = false

        guard !Task.isCancelled else {
            opening.finish()
            return .cancelled
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            opening.finish()
            return .fileMissing
        }
        if let origin, !origin.isStillOnScreen {
            opening.finish()
            return .cancelled
        }
        guard let window = origin?.window ?? keyWindow(), let presenter = topController(in: window) else {
            opening.finish()
            return .notShown
        }
        let controller = makeController(for: file, as: style, in: window, onDismiss: opening.finish)
        opening.controller = controller
        presenter.present(controller, animated: true)
        return .shown
    }

    private static func makeController(
        for file: URL, as style: Style, in window: UIWindow, onDismiss: @escaping () -> Void
    ) -> UIViewController {
        switch style {
        case .preview:
            return SingleFilePreviewController(url: file, onDismiss: onDismiss)
        case .share:
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            share.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
            if let popover = share.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            return share
        }
    }

    // MARK: - Where to show it

    /// The screen she tapped on: the top of the key window when she tapped.
    private struct Origin {
        let window: UIWindow
        weak var screen: UIViewController?

        /// False once that screen has closed (a sheet dismissed, its window
        /// gone) while the file was on its way.
        var isStillOnScreen: Bool {
            guard let screen, !screen.isBeingDismissed, screen.viewIfLoaded?.window === window else { return false }
            return window.windowScene?.activationState != .unattached
        }
    }

    private static func tapOrigin() -> Origin? {
        guard let window = keyWindow(), let screen = topController(in: window) else { return nil }
        return Origin(window: window, screen: screen)
    }

    /// The app's key window, whichever scene it is in; else a visible window
    /// of a scene in front.
    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let key = windows.first(where: \.isKeyWindow) { return key }
        let front = scenes.filter { $0.activationState == .foregroundActive }
        return front.flatMap(\.windows).first { !$0.isHidden }
    }

    /// The screen on top of `window`.
    private static func topController(in window: UIWindow) -> UIViewController? {
        guard var presenter = window.rootViewController else { return nil }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }
}

/// Quick Look for one file, keeping its own data source (Quick Look holds it
/// weakly) and telling the caller once, when it closes.
private final class SingleFilePreviewController: QLPreviewController, QLPreviewControllerDataSource,
    QLPreviewControllerDelegate {
    private let item: URL
    private var onDismiss: (() -> Void)?

    init(url: URL, onDismiss: @escaping () -> Void) {
        item = url
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        dataSource = self
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        item as NSURL
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        finish()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { finish() }
    }

    private func finish() {
        let done = onDismiss
        onDismiss = nil
        done?()
    }
}
#endif
