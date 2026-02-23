import SwiftUI

/// A reusable row component with a label and toggle
/// Standardizes the common pattern of HStack { Label, Spacer, Toggle }
struct ToggleRow: View {
    let title: String
    let systemImage: String?
    let color: Color
    @Binding var isOn: Bool
    
    init(
        _ title: String,
        systemImage: String? = nil,
        color: Color = .primary,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self._isOn = isOn
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(color)
            } else {
                Text(title)
                    .foregroundStyle(color)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ToggleRow("Simple Toggle", isOn: .constant(true))
        ToggleRow("With Icon", systemImage: "bell.fill", color: .blue, isOn: .constant(false))
        ToggleRow("Accent Color", systemImage: "star.fill", color: .orange, isOn: .constant(true))
    }
    .padding()
}
