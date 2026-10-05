import SwiftUI

/// The empty roll once the guide has taken this iPhone out of the class
/// (`AssistantBootstrapper.removedFromClass`). It used to read "No students
/// yet… It can take a minute after you join", for good. Leave takes her back
/// to joining, where a new invitation works.
struct AssistantRemovedFromClassView: View {
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var isLeaving = false
    @State private var leaveError: String?

    static let message = "You're no longer in this class. Ask your guide for a new invitation."

    var body: some View {
        ContentUnavailableView {
            Label("Not in This Class", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text(Self.message)
            if let leaveError {
                Text(leaveError)
            }
        } actions: {
            Button("Leave Classroom") {
                Task { await leave() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLeaving)
        }
    }

    private func leave() async {
        isLeaving = true
        leaveError = nil
        do {
            try await bootstrapper.leaveClassroom()
        } catch {
            leaveError = AssistantClassroomSheet.leaveMessage(for: error)
        }
        isLeaving = false
    }
}
