import SwiftUI

struct SubjectPillsView: View {
    let subjects: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(subjects, id: \.self) { subject in
                    let isSelected = selected?.caseInsensitiveCompare(subject) == .orderedSame
                    Button {
                        onSelect(subject)
                    } label: {
                        Text(subject)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isSelected ? AppColors.color(forSubject: subject) : Color(nsColor: .windowBackgroundColor))
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    SubjectPillsView(subjects: ["Geometry", "Language"], selected: "Geometry", onSelect: { _ in })
        .padding()
}
