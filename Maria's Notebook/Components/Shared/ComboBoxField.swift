import SwiftUI

/// A text field with a dropdown menu of existing options.
/// Allows free-text entry while guiding users toward existing values.
struct ComboBoxField: View {
    let title: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: AppTheme.Spacing.xsmall) {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)

                if !options.isEmpty {
                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(option) {
                                text = option
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose from existing \(title.lowercased())s")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "Math"

    VStack(spacing: 20) {
        ComboBoxField(
            title: "Subject",
            text: $text,
            options: ["Math", "Language", "Science", "Practical Life"]
        )
    }
    .padding()
    .frame(width: 300)
}
