import SwiftUI
import CoreData

/// The app once you've joined: Attendance, and Restock with the office run's
/// count on its tab.
///
/// The Restock model lives here rather than in its tab, so the badge is right
/// before the tab is ever opened, and follows the guide's changes as they
/// arrive from iCloud.
struct AssistantTabs: View {
    let coreDataStack: CoreDataStack

    enum Choice: Hashable {
        case attendance
        case restock
    }

    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var selection = Choice.attendance
    @State private var restock: AssistantRestockModel?

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
/// what changed meanwhile; back from the background, this phone's check-offs
/// are done with. A modifier of its own, so the scene phase's four changes on
/// every trip away and back redraw only this, not the tabs
/// (`AssistantReloadOnReturn`).
private struct RestockFollowsScene: ViewModifier {
    let model: AssistantRestockModel?
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the app went to the background since it was last active: a
    /// glance at Control Center only passes through inactive.
    @State private var wentAway = false

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { oldPhase, phase in
            if phase == .active, oldPhase != .active {
                if wentAway { model?.forgetCheckOffs() }
                wentAway = false
                model?.load()
            } else if phase != .active {
                if phase == .background { wentAway = true }
                model?.flush()
            }
        }
    }
}
