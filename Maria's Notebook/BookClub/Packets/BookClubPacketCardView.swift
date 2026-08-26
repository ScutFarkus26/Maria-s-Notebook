import CoreData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct BookClubPacketCardView: View {
    let packet: CDBookClubPacket
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(packet.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !packet.author.isEmpty {
                    Text(packet.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let band = packet.gradeBand {
                        gradePill(band)
                    }
                    Spacer(minLength: 0)
                    if !packet.readingItems.isEmpty {
                        Label("\(packet.readingItems.count)", systemImage: "list.bullet")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !packet.themesArray.isEmpty {
                    themeChips
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        // Decoded through the shared cache — see `CachedThumbnail`. This card is a
        // `LazyVGrid` cell, so a decode in `body` runs on every scroll pass.
        if let image = CachedThumbnail.image(
            from: packet.thumbnailData,
            cacheKey: packet.objectID.uriRepresentation().absoluteString
        ) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "book.pages")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gradePill(_ band: StoryGradeBand) -> some View {
        Text(band.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }

    private var themeChips: some View {
        HStack(spacing: 4) {
            ForEach(packet.themesArray.prefix(3), id: \.self) { theme in
                StoryThemeChip(theme)
            }
            if packet.themesArray.count > 3 {
                Text("+\(packet.themesArray.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
