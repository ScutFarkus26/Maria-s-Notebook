import SwiftUI

struct NotesSection: View {
    @Binding var notes: String
    let separatorStrokeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSectionHeader(icon: "note.text", title: "Notes")
            TextEditor(text: $notes)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(separatorStrokeColor, lineWidth: 1)
                )
        }
    }
}
