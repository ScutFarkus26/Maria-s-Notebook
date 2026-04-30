import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct StoryCardView: View {
    let story: CDStory
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .overlay(alignment: .topTrailing) { statusBadge }
                .overlay { analyzingOverlay }
            VStack(alignment: .leading, spacing: 6) {
                Text(story.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if let band = story.gradeBand {
                        gradePill(band)
                    }
                    if story.gradeBand == nil && story.analysisStatus == .manual {
                        Text("Add details")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }

                if !story.themesArray.isEmpty {
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
        if let data = story.thumbnailData, let image = platformImage(from: data) {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
            #endif
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "book.pages")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var analyzingOverlay: some View {
        if story.analysisStatus == .analyzing || story.analysisStatus == .pending {
            StoryImportProgressView()
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch story.analysisStatus {
        case .failed:
            badge(systemName: "exclamationmark.triangle.fill", color: .red)
        case .stale:
            badge(systemName: "clock.arrow.circlepath", color: .orange)
        case .manual:
            badge(systemName: "pencil", color: .orange)
        default:
            EmptyView()
        }
    }

    private func badge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(color))
            .padding(8)
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
            ForEach(story.themesArray.prefix(3), id: \.self) { theme in
                StoryThemeChip(theme)
            }
            if story.themesArray.count > 3 {
                Text("+\(story.themesArray.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func platformImage(from data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }
}
