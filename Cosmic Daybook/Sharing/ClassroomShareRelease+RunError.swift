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
            }
        }
    }

    /// The plain sentence and the detail for whatever stopped a run: a `RunError` speaks
    /// for itself; anything else (a CloudKit error reading the server) is translated, its
    /// raw text kept for Details.
    static func stopMessage(for error: Error) -> (message: String, details: String) {
        if let runError = error as? RunError {
            return (runError.errorDescription ?? "", runError.details)
        }
        let ns = error as NSError
        return (
            "Couldn't hear back from iCloud, so this stopped. Nothing is lost. "
                + "Check you're online, then run it again to finish.",
            "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
        )
    }
}
