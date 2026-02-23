import SwiftUI

/// A reusable labeled picker component
/// Standardizes the pattern of labeled pickers with consistent styling
struct LabeledPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: Content
    
    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Picker(title, selection: $selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

#Preview {
    @Previewable @State var selectedOption = "Option 1"
    
    VStack(spacing: 20) {
        LabeledPicker("Choose Option", selection: $selectedOption) {
            Text("Option 1").tag("Option 1")
            Text("Option 2").tag("Option 2")
            Text("Option 3").tag("Option 3")
        }
    }
    .padding()
}
