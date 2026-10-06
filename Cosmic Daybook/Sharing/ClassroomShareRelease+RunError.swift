import Foundation

// Why a run of `ClassroomShareRelease` stopped: a plain sentence for the guide and the
// technical reason for the log and the Details disclosure. A sync failure's own text
// (`StoreSyncFailure.message`) and CloudKit's errors go under Details, never in the
// sentence.

nonisolated extension ClassroomShareRelease {

    enum RunError: LocalizedError, Equatable {
        case stopped(String)
        case timedOut(String)
        case copyVanished
        case originalVanished
        case copyLandedInShare
        case originalNotMirrored
        case storeUnavailable
        case anotherCopyOpen

        /// What the guide reads. Plain on purpose: the specifics are in `details`.
        var errorDescription: String? {
            switch self {
            case .stopped:
                return "iCloud sync stopped working, so this stopped too. Nothing is lost. "
                    + "Once sync is working again, run it again to finish."
            case .timedOut:
                return "iCloud took too long to answer, so this stopped. Nothing is lost; run it again later to finish."
            case .copyVanished:
                return "Something changed on another device during the run, so this stopped. Nothing is lost. "
                    + "Make sure every device has the latest Cosmic Daybook, then try again."
            case .originalVanished:
                return "Something changed on another device during the run, so this stopped. Nothing is lost. "
                    + "Run it again later."
            case .copyLandedInShare, .originalNotMirrored:
                return "Something unexpected happened, so this stopped. Nothing is lost. Try again later."
            case .storeUnavailable:
                return "Your notebook isn't open right now. Reopen the app and try again."
            case .anotherCopyOpen:
                return "Another copy of Cosmic Daybook opened your notebook, so this stopped. Nothing is lost. "
                    + "Quit that copy (Claude may have opened it), then run it again to finish."
            }
        }

        /// What actually happened, for the log and the Details disclosure.
        var details: String {
            switch self {
            case .stopped(let reason): return reason
            case .timedOut(let step): return "Timed out waiting for iCloud to confirm \(step)."
            case .copyVanished:
                return "A private copy disappeared before its original was removed; another device may be "
                    + "running an older build. That record was left in the share."
            case .originalVanished:
                return "A shared original left this Mac during the run while iCloud still has it. "
                    + "Its private copy was kept."
            case .copyLandedInShare: return "A copy was filed into a share instead of the private store."
            case .originalNotMirrored: return "A shared original had no CloudKit record to check."
            case .storeUnavailable: return "The private store isn't open."
            case .anotherCopyOpen: return "Another running copy of the app has the store open."
            }
        }
    }

    /// The plain sentence and the detail for whatever stopped a run: a `RunError` speaks
    /// for itself; anything else (a CloudKit error reading the server, a Core Data error
    /// saving here) is translated, its raw text kept for Details.
    static func stopMessage(for error: Error) -> (message: String, details: String) {
        if let runError = error as? RunError {
            return (runError.errorDescription ?? "", runError.details)
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            // A save or read here failed (a merge conflict with a change that arrived
            // mid-run, say): nothing to do with being online.
            return (
                "Something changed while this ran, so it stopped. Nothing is lost. Run it again.",
                "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
            )
        }
        return (
            "Couldn't hear back from iCloud, so this stopped. Nothing is lost. "
                + "Check you're online, then run it again to finish.",
            "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
        )
    }
}
