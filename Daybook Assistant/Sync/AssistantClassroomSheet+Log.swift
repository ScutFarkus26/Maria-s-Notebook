import SwiftUI

// The way to show the guide what's happening when marks won't send: the
// app's log since it was opened, as a text file to share
// (`AssistantSendingReport`). Until 2026-10-23 a stuck morning left nothing
// to look at but the sync line.

extension AssistantClassroomSheet {
    /// Not for the sample class, whose marks go nowhere.
    @ViewBuilder
    var logSection: some View {
        if !AssistantSampleClass.isActive {
            logSectionBody
        }
    }

    private var logSectionBody: some View {
        Section {
            ShareLink(
                item: AssistantSendingReport(),
                preview: SharePreview("Daybook Assistant log", image: Image(systemName: "doc.text"))
            ) {
                Label("Share the App's Log…", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("If marks aren't sending")
        } footer: {
            Text("A text file of what the app has done since you opened it: each try to send your marks "
                + "and what iCloud said back. If the marks keep saying not sent, send it to your guide, "
                + "who can see why. Nothing is sent on its own.")
        }
    }
}
