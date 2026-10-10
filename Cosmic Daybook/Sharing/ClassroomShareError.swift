import Foundation

/// Why sharing couldn't be set up or opened.
enum ClassroomShareError: LocalizedError, Equatable {
    case cloudKitInactive
    case sharedStoreUnavailable
    case assistantCannotCreateShare
    case noSeedRecordAvailable
    case shareStillSyncing
    case firstDownloadPending
    case mirroringStopped
    case otherShareZonesExist(Int)
    case notSetUp
    case shareHasNoStudents
    case shareContentsUnknown
    case anotherCopyOpen
    case pinNotSaved
    case earlierAttachStillRunning
    /// A resumed setup on a device that hasn't imported since the pin arrived.
    case classStillDownloading
    /// iCloud had no account when the notebook opened (`shareFilingPausedUntilReopen`).
    case iCloudNotReadyAtLaunch
    /// The iCloud account isn't ready yet (`ShareFilingHold.untilICloudReady`).
    case iCloudNotReadyYet

    /// The refusal for what holds filing into the share.
    init(_ hold: CloudKitSyncStatusService.ShareFilingHold) {
        switch hold {
        case .untilReopen: self = .iCloudNotReadyAtLaunch
        case .untilICloudReady: self = .iCloudNotReadyYet
        }
    }

    var errorDescription: String? {
        switch self {
        case .cloudKitInactive:
            return "iCloud sync isn't on. Turn on iCloud for Cosmic Daybook in \(SystemSettingsApp.name), "
                + "then try again."
        case .sharedStoreUnavailable:
            return "Classroom sharing can't start on this device right now. Quit and reopen the app, then try again."
        case .assistantCannotCreateShare:
            return "Only the lead guide can share the classroom."
        case .noSeedRecordAvailable:
            return "Add a student before sharing the classroom."
        case .shareStillSyncing:
            return "Your classroom's sharing is still coming down from iCloud. Wait for sync to finish, then try again."
        case .firstDownloadPending:
            return "The notebook is still downloading from iCloud. Set up sharing once it has finished."
        case .mirroringStopped:
            return "iCloud sync stopped working this session. Quit and reopen Cosmic Daybook, then try again."
        case .otherShareZonesExist(let count):
            let shares = count == 1 ? "a classroom share" : "\(count) classroom shares"
            return "iCloud already has \(shares) for this notebook, and sharing can only be set up once, " +
                "so nothing was changed."
        case .notSetUp:
            return "Classroom sharing isn't set up yet. Choose Set Up Classroom Sharing first."
        case .shareHasNoStudents:
            return "No students are shared yet, so an assistant would see an empty class. " +
                "Nothing was sent. Choose Set Up Classroom Sharing first."
        case .shareContentsUnknown:
            return "Couldn't check what your classroom share holds, so sharing didn't open. Try again in a moment."
        case .anotherCopyOpen:
            return "Another copy of Cosmic Daybook has the notebook open. Quit the other copy, then try again."
        case .pinNotSaved:
            return "Classroom sharing was started, but this device couldn't save it. Keep Cosmic Daybook open " +
                "and choose Set Up Classroom Sharing again to finish."
        case .earlierAttachStillRunning:
            return "Cosmic Daybook is still adding earlier changes to the classroom share. Try again in a " +
                "few minutes. If this keeps happening, quit and reopen the app."
        case .classStillDownloading:
            return "This device is still downloading the class from iCloud. Try again in a few minutes, "
                + "or quit and reopen the notebook."
        case .iCloudNotReadyAtLaunch:
            return CloudKitSyncStatusService.shareFilingPausedMessage
        case .iCloudNotReadyYet:
            return "iCloud isn't ready yet. Try again in a few minutes."
        }
    }
}
