import Foundation

// MARK: - CloudKit Configuration Service

/// Service for managing CloudKit configuration and status.
enum CloudKitConfigurationService {

    // MARK: - Container ID

    /// Returns the CloudKit container identifier from entitlements.
    /// This must match the container ID in the entitlements file.
    static func getContainerID() -> String? {
        "iCloud.DanielSDeBerry.MariasNoteBook"
    }

    // MARK: - Status

    /// CloudKit sync status summary.
    struct Status {
        let enabled: Bool
        let active: Bool
        let containerID: String
    }

    /// Returns a summary of CloudKit sync status.
    static func getStatus() -> Status {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        let active = UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive)
        let containerID = getContainerID() ?? "Unknown"
        return Status(enabled: enabled, active: active, containerID: containerID)
    }

    // MARK: - Error Handling

    /// Stores a CloudKit error for display in the UI.
    static func storeError(_ error: Error) {
        let errorDescription = (error as NSError?)?.localizedDescription ?? String(describing: error)
        if let nsError = error as NSError? {
            let userInfo = nsError.userInfo
            var detailedError = errorDescription
            if let underlyingError = userInfo[NSUnderlyingErrorKey] as? NSError {
                detailedError = underlyingError.localizedDescription
            } else if let errorMessage = userInfo[NSLocalizedDescriptionKey] as? String {
                detailedError = errorMessage
            }
            UserDefaults.standard.set(detailedError, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
        } else {
            UserDefaults.standard.set(errorDescription, forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
        }
    }

    /// Clears any stored CloudKit error.
    static func clearError() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cloudKitLastErrorDescription)
    }

    /// Marks CloudKit as active and clears any previous error.
    static func markActive() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.cloudKitActive)
        clearError()
    }

    /// Marks CloudKit as inactive.
    static func markInactive() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.cloudKitActive)
    }
}
