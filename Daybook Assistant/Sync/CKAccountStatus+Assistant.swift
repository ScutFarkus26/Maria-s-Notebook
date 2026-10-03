import CloudKit

extension CKAccountStatus {
    /// What's wrong with iCloud on this iPhone, in words she can act on, or
    /// nil when nothing is (or CloudKit couldn't say, which is usually
    /// momentary and not worth alarming anyone over).
    var assistantProblem: String? {
        switch self {
        case .noAccount:
            return "This iPhone isn't signed in to iCloud. Sign in from the top of the Settings app."
        case .restricted:
            return "iCloud is restricted on this iPhone, by Screen Time or a device profile."
        case .temporarilyUnavailable:
            return "iCloud is unavailable right now. Open Settings and check your Apple Account."
        case .available, .couldNotDetermine:
            return nil
        @unknown default:
            return nil
        }
    }
}
