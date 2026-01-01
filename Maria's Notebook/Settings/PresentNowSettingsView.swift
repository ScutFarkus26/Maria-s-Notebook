import SwiftUI

struct PresentNowSettingsView: View {
    @AppStorage("StudentsView.presentNow.excludedNames") private var presentNowExcludedNamesRaw: String = "danny de berry,lil dan d"
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude Students from Present Now")
                .font(.headline)
            Text("Enter names separated by commas or semicolons. Matching is case-insensitive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: 14))
                .frame(minHeight: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                )
            HStack {
                Spacer()
                Button("Reset to Default") {
                    draft = "danny de berry,lil dan d"
                }
                Button("Save") {
                    presentNowExcludedNamesRaw = draft
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { draft = presentNowExcludedNamesRaw }
    }
}
