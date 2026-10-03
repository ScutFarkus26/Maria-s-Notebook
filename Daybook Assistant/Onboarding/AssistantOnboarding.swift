import Foundation

/// What the first-run screens remember on this iPhone.
///
/// Two parts. The intro (Welcome, the practice grid, iCloud) shows before
/// joining, until she reaches the invitation page once; after that a relaunch
/// opens on the invitation page, with the intro a swipe back. The setup
/// (name, reminder, background, Siri, the tile symbols, All Set) shows once
/// after joining, over the attendance screen, until she finishes it.
///
/// Per iPhone, like the background and the reminder it sets: a new iPhone
/// walks through setup again, with her name already filled in from iCloud.
enum AssistantOnboarding {
    static let introSeenKey = "Assistant.onboarding.introSeen"
    static let setupDoneKey = "Assistant.onboarding.setupDone"

    static func introSeen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: introSeenKey)
    }

    static func markIntroSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: introSeenKey)
    }

    static func setupDone(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: setupDoneKey)
    }

    static func markSetupDone(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: setupDoneKey)
    }

    /// The setup shows until it's finished, and never over the sample class,
    /// which has nothing to set up.
    static func needsSetup(isSample: Bool, defaults: UserDefaults = .standard) -> Bool {
        if isSetupRequested { return true }
        return !isSample && !setupDone(defaults)
    }

    /// Launched with `-AssistantSetup` (with `-AssistantSampleClass`, say):
    /// setup shows every launch, for looking at it without a classroom.
    /// Always false in Release.
    static var isSetupRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AssistantSetup")
        #else
        false
        #endif
    }
}

/// The intro's practice grid: nine made-up children, marked by the real
/// grid's tap rule (`AttendanceRules.statusAfterTap`), so what she learns
/// here is what the class does. Nothing is stored or sent.
struct AssistantPracticeRoll: Equatable {
    static let names = ["Ari", "Maya", "Noah", "Leah", "Ezra", "Tamar", "Miriam", "Eli", "Rina"]

    private(set) var marks: [String: AttendanceStatus] = [:]
    private(set) var phase: AttendancePhase = .arrival

    func status(of name: String) -> AttendanceStatus {
        marks[name] ?? .unmarked
    }

    /// What a tap does in the real grid: during arrival it marks here or
    /// takes it back; once arrival is closed it marks late.
    mutating func tap(_ name: String) {
        guard let next = AttendanceRules.statusAfterTap(from: status(of: name), in: phase) else { return }
        marks[name] = next == .unmarked ? nil : next
    }

    /// Close Arrival: everyone not marked is absent, and taps mark late.
    mutating func closeArrival() {
        for name in Self.names where marks[name] == nil {
            marks[name] = .absent
        }
        phase = .late
    }

    mutating func reset() {
        self = AssistantPracticeRoll()
    }

    var hereCount: Int {
        Self.names.count { AssistantAttendanceViewModel.isHere(status(of: $0)) }
    }

    var absentCount: Int {
        Self.names.count { status(of: $0) == .absent }
    }

    var unmarkedCount: Int {
        Self.names.count { status(of: $0) == .unmarked }
    }
}
