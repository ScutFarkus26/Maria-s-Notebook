import SwiftUI

struct TestStudentsSettingsView: View {
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @State private var draftNames: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show Test Students", isOn: $showTestStudents)
            Text("Enter a comma or semicolon separated list of full names to treat as Test Students. Matching is case-insensitive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $draftNames)
                .font(.system(size: AppTheme.FontSize.body))
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
                Button("Restore Default") {
                    draftNames = "Danny De Berry,Lil Dan D"
                }
                Button("Save") {
                    testStudentNamesRaw = draftNames
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { draftNames = testStudentNamesRaw }
    }
}

#Preview {
    TestStudentsSettingsView()
}
