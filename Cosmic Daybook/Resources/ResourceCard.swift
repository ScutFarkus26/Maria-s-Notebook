import CoreData
import SwiftUI

/// Grid card for displaying a resource with PDF thumbnail, title, and category badge.
struct ResourceCard: View {
    let resource: CDResource
    let onTap: () -> Void
    var onViewDetails: (() -> Void)?
    var onOpen: (() -> Void)?
    var onPrint: (() -> Void)?
    let onDelete: () -> Void
    var onRename: (() -> Void)?
    var onChangeCategory: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens resource")
        .contextMenu {
            contextMenuContent
        }
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contextMenuContent: some View {
            if let onOpen {
                Button(action: onOpen) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
            }

            if let onPrint {
                Button(action: onPrint) {
                    Label("Print", systemImage: "printer")
                }
            }

            if let onViewDetails {
                Button(action: onViewDetails) {
                    Label("View Details", systemImage: "eye")
                }
            }

            if let onRename {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
            }

            if let onChangeCategory {
                Button(action: onChangeCategory) {
                    Label("Change Category", systemImage: "folder")
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }
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
