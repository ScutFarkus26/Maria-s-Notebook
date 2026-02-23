import SwiftUI

/// A reusable search field with consistent styling
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    
    init(_ placeholder: String = "Search", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
        .cornerRadius(UIConstants.CornerRadius.medium)
    }
}

#Preview {
    @Previewable @State var searchText = ""
    
    VStack(spacing: 16) {
        SearchField(text: $searchText)
        SearchField("Find students", text: $searchText)
    }
    .padding()
}
