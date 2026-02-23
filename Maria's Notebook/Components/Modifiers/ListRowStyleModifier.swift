import SwiftUI

/// A view modifier for consistent list row styling
/// Standardizes the pattern of padding + contentShape for interactive rows
struct ListRowStyleModifier: ViewModifier {
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    
    init(
        verticalPadding: CGFloat = AppTheme.Spacing.verySmall,
        horizontalPadding: CGFloat = AppTheme.Spacing.small
    ) {
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Apply consistent list row styling with padding and tap area
    func listRowStyle(
        verticalPadding: CGFloat = AppTheme.Spacing.verySmall,
        horizontalPadding: CGFloat = AppTheme.Spacing.small
    ) -> some View {
        modifier(ListRowStyleModifier(
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding
        ))
    }
}

#Preview {
    List {
        Text("Row with default style")
            .listRowStyle()
        
        Text("Row with custom padding")
            .listRowStyle(verticalPadding: 12, horizontalPadding: 16)
        
        HStack {
            Image(systemName: "star.fill")
            Text("Interactive row")
        }
        .listRowStyle()
    }
}
