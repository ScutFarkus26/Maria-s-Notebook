import SwiftUI

// Public enum so both views can see it
enum StudentMode: String, CaseIterable, Identifiable {
    case roster = "Roster"
    case age = "Ages"
    case birthday = "Birthday"
    case withdrawn = "Withdrawn"
    var id: String { rawValue }
}

struct StudentsRootView: View {
    // We keep the state here to persist it, but pass it down as a binding
    @AppStorage(UserDefaultsKeys.studentsRootViewMode) private var modeRaw: String = StudentMode.roster.rawValue

    private var mode: StudentMode {
        get { StudentMode(rawValue: modeRaw) ?? .roster }
        set { modeRaw = newValue.rawValue }
    }

    var body: some View {
        StudentsView(
            mode: Binding(get: { mode }, set: { newValue in modeRaw = newValue.rawValue })
        )
    }
}
