import CoreData
import SwiftUI

/// A file's card in Resources › Files: its first page, title, category,
/// favorite star and first tags. The list opens it and gives it its menu.
struct ResourceCard: View {
    @ObservedObject var resource: CDResource
    let isSelected: Bool

    var body: some View {
        cardContent
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            thumbnailView
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()

            // Title
            Text(resource.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Category + favorite
            HStack(spacing: 4) {
                Image(systemName: resource.category.icon)
                    .font(.caption2)
                Text(resource.category.rawValue)
                    .font(.caption2)

                if resource.isFavorite {
                    Spacer()
                    Image(systemName: SFSymbol.Shape.starFill)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)

            // Tags (show first 2)
            if !resource.tagsArray.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(resource.tagsArray.prefix(2), id: \.self) { tag in
                        TagBadge(tag: tag, compact: true)
                    }
                    if resource.tagsArray.count > 2 {
                        Text("+\(resource.tagsArray.count - 2)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.hint),
            stroke: isSelected ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.light),
            lineWidth: isSelected ? 2 : 1,
            style: .continuous
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailView: some View {
        // Decoded through the shared cache — see `CachedThumbnail`. This card is a
        // `LazyVGrid` cell, so a decode in `body` runs on every scroll pass.
        if let image = CachedThumbnail.image(
            from: resource.thumbnailData,
            cacheKey: resource.objectID.uriRepresentation().absoluteString
        ) {
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback icon
            VStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        }
    }

}
