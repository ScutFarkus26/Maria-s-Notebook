#if DEBUG
import SwiftUI

struct TestStudentsSettingsView: View {
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @State private var draftNames: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show Test Students", isOn: $showTestStudents)
            
            if !showTestStudents {
                #if os(macOS)
                Text(
                    "When hidden, test students are excluded from Students, Today, Attendance, Planning, "
                    + "Presentations, Checklist, Open Work, Logs, Projects, Notes, Inbox, and related views."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                #else
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test students are excluded from all views:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ExclusionItem("Students")
                            ExclusionItem("Today")
                            ExclusionItem("Attendance")
                            ExclusionItem("Planning")
                            ExclusionItem("Presentations")
                            ExclusionItem("Checklist")
                            ExclusionItem("Open Work")
                            ExclusionItem("Logs")
                            ExclusionItem("Projects")
                            ExclusionItem("Notes")
                            ExclusionItem("Inbox")
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
                    )
                #endif
            }
            
            Text(
                "Enter a comma or semicolon separated list of full names to treat as Test Students."
                + " Matching is case-insensitive."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $draftNames)
                .font(AppTheme.ScaledFont.body)
                .frame(minHeight: 80)
                #if os(iOS)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
                    )
                #endif
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                )
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    draftNames = "Danny De Berry,Lil Dan D"
                }
                Button("Save") {
                    testStudentNamesRaw = draftNames
                }
                .buttonStyle(.borderedProminent)
                #if os(macOS)
                .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        .onAppear { draftNames = testStudentNamesRaw }
        .onChange(of: showTestStudents) { _, _ in SettingsCategory.markModified(.advanced) }
        .onChange(of: testStudentNamesRaw) { _, _ in SettingsCategory.markModified(.advanced) }
    }
}

private struct ExclusionItem: View {
    let name: String
    
    init(_ name: String) {
        self.name = name
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TestStudentsSettingsView()
}
#endif
