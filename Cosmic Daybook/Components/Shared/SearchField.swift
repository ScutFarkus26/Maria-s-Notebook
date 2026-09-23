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

/// The same field inside a drawn box: a soft fill with a hairline border.
///
/// Reference lists (procedures, supplies) sit it above a plain `List` where
/// the unbordered `SearchField` would have nothing to separate it from the
/// rows beneath.
struct BorderedSearchField: View {
    @Binding var text: String
    let placeholder: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack {
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
        .padding(10)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.hint),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.subtle),
            style: .continuous
        )
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SearchFieldPreview: View {
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 16) {
            SearchField(text: $searchText)
            SearchField("Find students", text: $searchText)
        }
        .padding()
    }
}

#Preview {
    SearchFieldPreview()
}
