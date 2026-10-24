import SwiftUI
import CoreData

/// The app once you've joined: Attendance, Restock with the office run's
/// count on its tab, and the class's Schedule (read only).
///
/// The Restock model lives here rather than in its tab, so the badge is right
/// before the tab is ever opened, and follows the guide's changes as they
/// arrive from iCloud while the app is on screen.
struct AssistantTabs: View {
    let coreDataStack: CoreDataStack

    enum Choice: Hashable {
        case attendance
        case restock
        case schedule
    }

    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var selection = AssistantScheduleTab.isRequestedAtLaunch ? Choice.schedule : .attendance
    @State private var restock: AssistantRestockModel?
    /// The first run after joining: name, reminder, background and the rest.
    @State private var showingSetup = false
    @AppStorage(AssistantOnboarding.setupDoneKey) private var setupDone = false
    /// Where `ClassroomIdentity.displayName` is kept, watched so the name
    /// sheet goes the moment she has a name, and comes when she has none.
    @AppStorage(UserDefaultsKeys.classroomIdentityDisplayName) private var storedName: String?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Attendance", systemImage: "square.grid.2x2", value: Choice.attendance) {
                AssistantAttendanceView(coreDataStack: coreDataStack)
            }
            Tab("Restock", systemImage: "shippingbox", value: Choice.restock) {
                if let restock {
                    AssistantRestockView(model: restock)
                } else {
                    ProgressView()
                }
            }
            .badge(restock?.officeRunCount ?? 0)
            Tab("Schedule", systemImage: "calendar.day.timeline.left", value: Choice.schedule) {
                AssistantScheduleTab(coreDataStack: coreDataStack)
            }
        }
        .task {
            let model = restock ?? makeRestock()
            // Staples, needs, levels and names all arrive by import.
            if let storeID = coreDataStack.sharedPersistentStore?.identifier {
                await model.followRemoteImports(into: storeID)
            }
        }
        .onChange(of: selection) { _, choice in
            // Back on Restock: the check-offs from before are done with.
            if choice == .restock { restock?.forgetCheckOffs() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .assistantShowToday)) { _ in
            selection = .attendance
        }
        .onReceive(NotificationCenter.default.publisher(for: .restockChangedBySiri)) { _ in
            // A level or a need set with Siri while the app was open.
            restock?.load(reconcile: false)
        }
        .modifier(RestockFollowsScene(model: restock))
        .modifier(ReminderSwitchesFollower())
        // The one place the first run asks anything (review (d), #2): setup on
        // the first run after joining, then one name sheet whenever a name is
        // missing in the real class, after an Apple Account change too
        // (`AssistantBootstrapper.readAccountAgain`). While setup is up the
        // sheet waits; a name given in setup answers it.
        .fullScreenCover(isPresented: $showingSetup) {
            AssistantSetupFlow { showingSetup = false }
        }
        .sheet(isPresented: askingForName) {
            AssistantNameSheet(isRequired: true)
        }
        .task {
            if AssistantOnboarding.needsSetup(isSample: AssistantSampleClass.isActive) { showingSetup = true }
        }
        .onChange(of: hasName) { _, has in
            if has, bootstrapper.askForNameAgain { bootstrapper.askForNameAgain = false }
        }
    }

    private var hasName: Bool { storedName?.trimmed().isEmpty == false }

    /// Shows while `AssistantFirstRun.asksForName` says so. The sheet can't be
    /// put away without a name, and saving one sets it before the sheet goes
    /// (`AssistantNameSheet.commit`), so there's nothing to do on the way out.
    private var askingForName: Binding<Bool> {
        Binding(
            get: {
                AssistantFirstRun.asksForName(
                    setupShowing: showingSetup, setupDone: setupDone,
                    isSample: AssistantSampleClass.isActive, hasName: hasName
                )
            },
            set: { _ in }
        )
    }

    private func makeRestock() -> AssistantRestockModel {
        // The sample class's changes go into no share.
        let isSample = AssistantSampleClass.isActive
        let model = AssistantRestockModel.live(
            context: coreDataStack.viewContext,
            container: isSample ? nil : coreDataStack.container,
            guideName: { [bootstrapper] in bootstrapper.guideName }
        )
        model.load()
        restock = model
        return model
    }
}

/// A burst of Restock taps saves before the app goes, and coming back reads
/// what changed meanwhile (imports don't reload the tab while it's away);
/// back from the background, this phone's check-offs are done with. A
/// modifier of its own, so the scene phase's four changes on every trip away
/// and back redraw only this, not the tabs (`AssistantReloadOnReturn`).
private struct RestockFollowsScene: ViewModifier {
    let model: AssistantRestockModel?
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the app went to the background since it was last active: a
    /// glance at Control Center only passes through inactive.
    @State private var wentAway = false

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { oldPhase, phase in
            if phase == .active, oldPhase != .active {
                // The load below shows what arrived while away.
                model?.followScene(isActive: true)
                if wentAway { model?.forgetCheckOffs() }
                wentAway = false
                model?.load()
            } else if phase != .active {
                model?.followScene(isActive: false)
                if phase == .background { wentAway = true }
                model?.flush()
            }
        }
    }
}
