import SwiftUI

// MARK: - Reusable Button Styles

struct RoundedActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(color))
        }
        .buttonStyle(.plain)
    }
}

struct IconActionButton: View {
    let icon: String
    let color: Color
    let backgroundColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(backgroundColor))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric Display Components

struct MetricStatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                
                Text(value)
                    .font(.system(size: AppTheme.FontSize.titleMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }
}

struct QualityMetricBox: View {
    let level: Double
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(color.opacity(level >= Double(index) ? 1.0 : 0.2))
                        .frame(width: 8, height: 8)
                }
            }
            
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }
}

struct ActionItemBox: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: AppTheme.FontSize.body, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(label)
                    .font(.system(size: AppTheme.FontSize.captionSmall, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
    }
}

// MARK: - Detail Section Card

struct DetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    let trailing: () -> Trailing
    let content: () -> Content
    
    init(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = trailing
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                
                Text(title)
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                
                Spacer()
                
                trailing()
            }
            
            content()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Common UI Helpers

struct StyledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $text)
                .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }
}

struct CategoryBadge: View {
    let category: NoteCategory
    
    var body: some View {
        if category != .general {
            HStack(spacing: 4) {
                Circle()
                    .fill(categoryColor(for: category))
                    .frame(width: 6, height: 6)
                Text(category.rawValue.capitalized)
                    .font(.system(size: AppTheme.FontSize.captionSmall, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(categoryColor(for: category).opacity(0.1)))
        }
    }
    
    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .general: return .gray
        case .behavioral: return .orange
        case .academic: return .blue
        case .social: return .green
        case .emotional: return .pink
        case .health: return .red
        case .attendance: return .purple
        }
    }
}

struct BehaviorPill: View {
    let behavior: String
    
    var body: some View {
        Text(behavior)
            .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
            .foregroundStyle(behaviorColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(behaviorColor.opacity(0.15)))
    }
    
    private var behaviorColor: Color {
        switch behavior {
        case "Breakthrough!": return .green
        case "Struggled": return .orange
        case "Needs reteaching": return .red
        case "Ready for check-in", "Ready for assessment": return .blue
        case "Asked for help": return .purple
        case "Helped peer": return .teal
        default: return .gray
        }
    }
}

struct FlagRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
            
            Text(text)
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
    }
}
