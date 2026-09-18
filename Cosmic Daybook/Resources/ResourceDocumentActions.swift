import Foundation
@preconcurrency import PDFKit
import OSLog

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ResourceDocumentActions {
    private static let logger = Logger.resources

    static func open(_ resource: CDResource) {
        guard let url = exportableFileURL(for: resource) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        guard let (window, presenter) = activePresentationContext() else { return }
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(
                x: window.bounds.midX,
                y: window.bounds.midY,
                width: 1,
                height: 1
            )
        }
        presenter.present(activityController, animated: true)
        #endif
    }

    static func print(_ resource: CDResource) {
        guard let url = exportableFileURL(for: resource) else { return }
        #if os(iOS)
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = resource.title
        printInfo.outputType = .general
        printController.printInfo = printInfo
        printController.printingItem = url

        if UIDevice.current.userInterfaceIdiom == .pad,
           let (window, _) = activePresentationContext() {
            let sourceRect = CGRect(
                x: window.bounds.midX,
                y: window.bounds.midY,
                width: 1,
                height: 1
            )
            printController.present(from: sourceRect, in: window, animated: true)
        } else {
            printController.present(animated: true)
        }
        #else
        guard let document = PDFDocument(url: url),
              let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo,
              let operation = document.printOperation(
                for: printInfo,
                scalingMode: .pageScaleNone,
                autoRotate: true
              ) else {
            return
        }

        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        operation.showsPrintPanel = true

        if let keyWindow = NSApp.keyWindow {
            operation.runModal(for: keyWindow, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        #endif
    }

    private static func exportableFileURL(for resource: CDResource) -> URL? {
        guard !resource.fileRelativePath.isEmpty else { return nil }
        do {
            let url = try ResourceFileStorage.resolve(relativePath: resource.fileRelativePath)
            #if os(macOS)
            return url
            #else
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportFilename(for: resource), isDirectory: false)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            return destinationURL
            #endif
        } catch {
            logger.warning("Failed to prepare resource document: \(error, privacy: .public)")
            return nil
        }
    }

    private static func exportFilename(for resource: CDResource) -> String {
        let baseName = ResourceFileStorage.sanitizedExportFilename(resource.title)
        return baseName.hasSuffix(".pdf") ? baseName : "\(baseName).pdf"
    }

    #if os(iOS)
    private static func activePresentationContext() -> (window: UIWindow, presenter: UIViewController)? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
            var presenter = window.rootViewController
        else {
            return nil
        }

        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        return (window, presenter)
    }
    #endif
}
