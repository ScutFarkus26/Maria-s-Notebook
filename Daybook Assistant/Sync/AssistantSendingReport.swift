import Foundation
import CoreTransferable
import OSLog
import UIKit
import UniformTypeIdentifiers

/// A plain text file of how sending stands on this iPhone and what the app
/// has logged since it was opened, for a morning when marks won't send and
/// nobody can see why from the Mac.
///
/// Nicole's marks sat on her phone twice (2026-10-22, 2026-10-23), and all
/// anyone could go on was the sync line. The app's own log names each try
/// and why it stopped (the `shareAttach`, `ClassroomShareAttach` and
/// `AttendanceShare` categories), and Core Data logs its uploads of the
/// shared store, and their errors, in the same process. Both are here, with
/// the phone's network and power as the app sees them. She shares it from
/// the Classroom screen (Messages, AirDrop) to the guide
/// (`AssistantClassroomSheet.logSection`).
///
/// Only this run of the app: iOS lets an app read its own process's log, not
/// the phone's, so it's worth sharing while the marks are still waiting,
/// before the app is quit. Nothing is sent anywhere by itself.
nonisolated struct AssistantSendingReport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { _ in
            SentTransferredFile(try await write())
        }
    }

    /// The file's name as it lands in Messages or on the Mac.
    static let fileName = "Daybook Assistant log.txt"

    /// How many log lines at most, the latest kept: a morning of tries is a
    /// few hundred; a day of Core Data's chatter could be thousands.
    static let maxLogLines = 3_000

    /// Writes the report to the temporary folder and returns the file.
    static func write() async throws -> URL {
        let standing = await currentStanding()
        let log = try await logLines()
        let text = text(standing: standing, log: log)
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - How sending stands

    /// The lines at the top: the app and phone, its network and power as
    /// the app sees them, what waits, and the class. A value, so the tests
    /// can make one.
    struct Standing {
        var version: String
        var system: String
        var now: Date
        var network: AssistantNetworkWatch.PathState?
        var lowPowerMode: Bool
        var waiting: Int
        var offline: Bool
        var stuck: Bool
        var lastEditSave: Double
        var lastExportStart: Double
        var lastImportEnd: Double
        var classCode: String?

        var lines: [String] {
            let networkLine: String = if let network {
                "\(AssistantSendingReport.name(of: network.interface)), "
                    + "\(network.usable ? "usable" : "not usable"), "
                    + "Low Data Mode \(network.lowDataMode ? "on" : "off")"
            } else {
                "not known yet"
            }
            let time = Date.FormatStyle(date: .abbreviated, time: .shortened)
            func when(_ seconds: Double) -> String {
                seconds > 0 ? Date(timeIntervalSince1970: seconds).formatted(time) : "never"
            }
            return [
                "Daybook Assistant log",
                "Version \(version), \(system)",
                "Written \(now.formatted(time))",
                "",
                "Network: \(networkLine)",
                "Low Power Mode: \(lowPowerMode ? "on" : "off")",
                "Marks waiting to send: \(waiting)"
                    + (offline ? " (iCloud couldn't be reached on the last try)" : "")
                    + (stuck ? " (a send has run past its time limit)" : ""),
                "Last edit saved: \(when(lastEditSave)); last upload began: \(when(lastExportStart)); "
                    + "class last updated: \(when(lastImportEnd))",
                "Class code: \(classCode ?? "none")"
            ]
        }
    }

    /// This iPhone's standing, read on the main actor where the app's state
    /// lives.
    @MainActor
    private static func currentStanding() -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        let attacher = AssistantShareAttacher.shared
        let record = AssistantStack.syncRecord
        let watch = AssistantStack.networkWatch
        let classCode = AssistantStack.current.flatMap { stack in
            CDClassroomMembership.pinnedZoneName(in: stack.viewContext)
                .map(CDClassroomMembership.classroomID(forZone:))
        }
        return Standing(
            version: "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
            system: "\(device.systemName) \(device.systemVersion)",
            now: Date(),
            network: watch?.current,
            lowPowerMode: watch?.lowPowerMode ?? ProcessInfo.processInfo.isLowPowerModeEnabled,
            waiting: attacher.pendingCount,
            offline: attacher.isOffline,
            stuck: attacher.sendingLooksStuck,
            lastEditSave: record?.lastEditSave ?? 0,
            lastExportStart: record?.lastExportStart ?? 0,
            lastImportEnd: record?.lastImportEnd ?? 0,
            classCode: classCode
        ).lines
    }

    static func name(of interface: AssistantNetworkWatch.Interface) -> String {
        switch interface {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wired: "Wired"
        case .other: "Other network"
        }
    }

    // MARK: - The log

    /// The app's own entries since it was opened, and Core Data's about its
    /// uploads and errors, oldest first, as lines. Off the main actor: the
    /// read walks the process's whole log.
    @concurrent
    private static func logLines() async throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let own = Bundle.main.bundleIdentifier ?? ""
        let predicate = NSPredicate(format: "subsystem == %@ OR subsystem == %@", own, coreDataSubsystem)
        let clock = Date.FormatStyle(date: .omitted, time: .standard)
        var lines: [String] = []
        for case let entry as OSLogEntryLog in try store.getEntries(matching: predicate) {
            if entry.subsystem == coreDataSubsystem, !keepsCoreDataLine(entry.composedMessage) { continue }
            let level = name(of: entry.level)
            lines.append("\(entry.date.formatted(clock))  \(entry.category)  \(level): \(entry.composedMessage)")
        }
        return Array(lines.suffix(maxLogLines))
    }

    static let coreDataSubsystem = "com.apple.coredata"

    /// Which of Core Data's lines are worth the space: its uploads, imports,
    /// setup and errors, not every fetch. Pure, for the tests.
    static func keepsCoreDataLine(_ message: String) -> Bool {
        ["export", "import", "error", "share", "setup", "mirroring"]
            .contains { message.localizedCaseInsensitiveContains($0) }
    }

    private static func name(of level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "log"
        @unknown default: "log"
        }
    }

    // MARK: - The file

    /// The whole report. Pure, for the tests.
    static func text(standing: [String], log: [String]) -> String {
        var parts = standing
        parts.append("")
        parts.append("What the app has logged since it was opened (\(log.count) lines):")
        parts.append("")
        parts += log.isEmpty ? ["(nothing yet)"] : log
        return parts.joined(separator: "\n") + "\n"
    }
}
