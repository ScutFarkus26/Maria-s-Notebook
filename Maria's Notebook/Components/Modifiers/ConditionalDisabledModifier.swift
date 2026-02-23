import SwiftUI

/// A view modifier that disables a view and reduces opacity based on a condition
/// Standardizes the pattern of .opacity(condition ? 1 : 0.4).disabled(!condition)
struct ConditionalDisabledModifier: ViewModifier {
    let condition: Bool
    let disabledOpacity: Double
    
    init(condition: Bool, disabledOpacity: Double = 0.4) {
        self.condition = condition
        self.disabledOpacity = disabledOpacity
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(condition ? disabledOpacity : 1)
            .disabled(condition)
    }
}

extension View {
    /// Conditionally disable a view with reduced opacity
    /// - Parameters:
    ///   - condition: When true, the view is disabled
    ///   - disabledOpacity: Opacity to apply when disabled (default 0.4)
    func conditionalDisabled(_ condition: Bool, disabledOpacity: Double = 0.4) -> some View {
        modifier(ConditionalDisabledModifier(condition: condition, disabledOpacity: disabledOpacity))
    }
}

#Preview {
    VStack(spacing: 20) {
        Button("Enabled Button") {}
            .conditionalDisabled(false)
        
        Button("Disabled Button") {}
            .conditionalDisabled(true)
        
        Button("Custom Opacity") {}
            .conditionalDisabled(true, disabledOpacity: 0.2)
    }
    .padding()
}
