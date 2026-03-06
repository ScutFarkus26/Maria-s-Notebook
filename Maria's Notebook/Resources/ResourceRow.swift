import SwiftUI

/// Compact list row for displaying a resource.
struct ResourceRow: View {
    let resource: Resource

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: resource.category.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            // Title and metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(resource.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if resource.fileSizeBytes > 0 {
                        Text(resource.fileSizeFormatted)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(resource.tags.prefix(3), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                }
            }

            Spacer()

            // Favorite indicator
            if resource.isFavorite {
                Image(systemName: SFSymbol.Shape.starFill)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            // Date
            Text(resource.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
