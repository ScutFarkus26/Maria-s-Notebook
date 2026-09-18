import SwiftUI

struct MeetingSessionWindowPayload: Codable, Hashable {
    let studentID: UUID
    let scheduledMeetingID: UUID?
}

struct MeetingSessionWindowHost: View {
    let payload: MeetingSessionWindowPayload

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ScheduledMeetingSessionSheet(studentID: payload.studentID) {
            if let meetingID = payload.scheduledMeetingID {
                MeetingScheduler.clearMeeting(id: meetingID, context: viewContext)
            }
            dismissWindow(id: "MeetingSessionWindow", value: payload)
        }
        .navigationTitle("Student Meeting")
    }
}
