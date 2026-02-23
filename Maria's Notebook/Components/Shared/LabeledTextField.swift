import SwiftUI

/// A reusable labeled text field component
/// Standardizes the pattern of VStack { Label, TextField }
struct LabeledTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    
    init(
        _ title: String,
        text: Binding<String>,
        placeholder: String = "",
        axis: Axis = .horizontal
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.axis = axis
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LabeledTextField("Name", text: .constant("John Doe"))
        LabeledTextField("Email", text: .constant(""), placeholder: "Enter email")
        LabeledTextField("Notes", text: .constant(""), placeholder: "Enter notes", axis: .vertical)
    }
    .padding()
}
