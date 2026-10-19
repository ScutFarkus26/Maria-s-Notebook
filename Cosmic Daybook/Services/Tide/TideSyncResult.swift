// TideSyncResult.swift
// What one run of the Tide sharing did, or why it stopped.

import Foundation

/// What one run did, or why it stopped.
enum TideSyncResult: Equatable {
    case synced(TideSyncReport)
    /// The first run's matches, waiting for Danny; nothing written.
    case needsFirstRunOK(TideFirstRunProposal)
    case stopped(TideSyncProblem)
}

/// What a run carried across.
struct TideSyncReport: Equatable {
    var sent = 0
    var pulled = 0
    var closedHere = 0
    var tickedInTide = 0
    var relinked = 0
    /// Linked actions given their notebook line this run.
    var marked = 0
    /// Titles Tide wouldn't take.
    var notSent: [String] = []
    /// Ticks Tide couldn't aim: its list has more than one action with the
    /// words. Asked again every run.
    var notTicked: [String] = []
    /// Tide's own words for what it refused, for the Details disclosure.
    var details: [String] = []
    /// The list for new to-dos isn't among Tide's lists any more.
    var destinationGone = false
    /// The saved heading for new to-dos isn't in that list any more.
    var headingGone: String?
    /// The list changed while sending, or Tide wasn't ready: the rest go on
    /// the next run.
    var tryAgain = false
}

/// Why a run stopped before writing anything more.
enum TideSyncProblem: Equatable {
    case tideNotRunning
    case timedOut
    case tokenRefused
    case stillOpening
    case noArea
    case saveFailed
    case other(details: String)

    init(_ error: Error) {
        switch error {
        case let transport as TideTransportError:
            switch transport {
            case .notRunning: self = .tideNotRunning
            case .timedOut: self = .timedOut
            case .tokenRefused: self = .tokenRefused
            case .unexpectedReply(let detail): self = .other(details: detail)
            }
        case let tool as TideToolError:
            self = tool.isStillOpening ? .stillOpening : .other(details: tool.details)
        default:
            self = .other(details: String(describing: type(of: error)))
        }
    }

    /// A problem reading the area: a refusal means Tide has no such area.
    init(readingArea error: Error) {
        if case TideToolError.refused = error {
            self = .noArea
        } else {
            self.init(error)
        }
    }

    /// The status line.
    var message: String {
        switch self {
        case .tideNotRunning: TideSyncMessages.tideNotRunning
        case .timedOut: TideSyncMessages.tideTimedOut
        case .tokenRefused: TideSyncMessages.tokenRefused
        case .stillOpening: TideSyncMessages.tideStillOpening
        case .noArea: TideSyncMessages.noArea
        case .saveFailed: TideSyncMessages.saveFailed
        case .other: TideSyncMessages.unexpectedReply
        }
    }

    /// The Details disclosure, when there's something worth keeping.
    var details: String? {
        if case .other(let details) = self { return details }
        return nil
    }

    var detailLines: [String] { details.map { [$0] } ?? [] }
}

/// The first run's proposal, shown in Settings until Danny confirms.
struct TideFirstRunProposal: Equatable {
    struct Match: Equatable, Identifiable {
        let notebookID: UUID
        let notebookTitle: String
        let tideLink: String
        let tideText: String
        let listName: String
        let score: Double
        /// An automatic work check-in: linked if kept, never sent.
        var isCheckIn = false

        var id: UUID { notebookID }
    }

    var matches: [Match]
    /// Notebook to-dos that go to Tide once confirmed.
    var toSend: Int
    /// Tide to-dos that show in the notebook once confirmed.
    var toShow: Int
    /// The list new to-dos go to.
    var destinationName: String
}

/// Tide's days, "YYYY-MM-DD", on the notebook's calendar.
nonisolated enum TideDay {
    static func date(_ text: String?, calendar: Calendar) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func string(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func sameDay(_ lhs: Date?, _ rhs: Date?, _ calendar: Calendar) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): calendar.isDate(lhs, inSameDayAs: rhs)
        default: false
        }
    }
}
