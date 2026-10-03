import SwiftUI
import PhotosUI

/// Classroom → Background: every background as a small page with four tiles
/// on it (here, not marked, absent, late), so she chooses by whether the
/// tiles still read, not by a swatch. A pick applies at once.
struct AssistantWallpaperPicker: View {
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue
    @State private var photoItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?
    private let photo = AssistantWallpaperPhoto.shared

    private var current: AssistantWallpaper { AssistantWallpaper.resolved(wallpaperRaw) }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AssistantWallpaper.allCases.filter { $0 != .photo }) { wallpaper in
                    Button {
                        wallpaperRaw = wallpaper.rawValue
                    } label: {
                        WallpaperPreview(wallpaper: wallpaper, isSelected: current == wallpaper)
                    }
                    .buttonStyle(.plain)
                }
                photoCell
            }
            .padding(16)

            Text("Only on this iPhone. Your guide doesn't see it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { photo.loadIfNeeded() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoCell: some View {
        if photo.image != nil {
            VStack(spacing: 8) {
                Button {
                    wallpaperRaw = AssistantWallpaper.photo.rawValue
                } label: {
                    WallpaperPreview(wallpaper: .photo, isSelected: current == .photo)
                }
                .buttonStyle(.plain)
                HStack(spacing: 16) {
                    PhotosPicker("Change", selection: $photoItem, matching: .images)
                    Button("Remove", role: .destructive, action: removePhoto)
                }
                .font(.footnote.weight(.medium))
                .disabled(isImporting)
            }
        } else {
            // The label closure isn't main-actor isolated, so it gets the
            // state as values instead of reading it.
            PhotosPicker(selection: $photoItem, matching: .images) { [isImporting, importError] in
                ChoosePhotoLabel(isImporting: isImporting, importError: importError)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        isImporting = true
        importError = nil
        defer {
            isImporting = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AssistantWallpaperPhoto.ImportError.unreadable
            }
            try await photo.save(data)
            wallpaperRaw = AssistantWallpaper.photo.rawValue
        } catch {
            importError = "Couldn't use that photo. Try another."
        }
    }

    private func removePhoto() {
        photo.remove()
        if current == .photo || wallpaperRaw == AssistantWallpaper.photo.rawValue {
            wallpaperRaw = AssistantWallpaper.standard.rawValue
        }
    }
}

/// The empty photo cell: a blank page with "Choose Photo…", a spinner while
/// a pick imports, or the import error in red.
private struct ChoosePhotoLabel: View {
    let isImporting: Bool
    let importError: String?

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(height: WallpaperPreview.height)
                .overlay {
                    if isImporting {
                        ProgressView()
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text(importError ?? "Choose Photo…")
                                .font(.footnote.weight(.medium))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(importError == nil ? Color.accentColor : .red)
                    }
                }
            Text("Photo")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

/// One background as a small page, with four sample tiles in the grid's own
/// fills and borders, and its name under it.
struct WallpaperPreview: View {
    let wallpaper: AssistantWallpaper
    let isSelected: Bool

    static let height: CGFloat = 150

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    SampleTile(name: "Ari", status: .present, quiet: wallpaper.isQuiet)
                    SampleTile(name: "Maya", status: .unmarked, quiet: wallpaper.isQuiet)
                }
                HStack(spacing: 6) {
                    SampleTile(name: "Noah", status: .absent, quiet: wallpaper.isQuiet)
                    SampleTile(name: "Leah", status: .tardy, quiet: wallpaper.isQuiet)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            // Behind, so the sky's tall wash can't stretch the page.
            .background {
                AssistantBackdrop(isToday: true, isLate: false, hereFraction: 0.5, wallpaper: wallpaper)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
            Label {
                Text(wallpaper.title)
            } icon: {
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wallpaper.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A small tile in the grid's style: solid green here, outlined unmarked,
/// dashed absent, a clock for late.
private struct SampleTile: View {
    let name: String
    let status: AttendanceStatus
    let quiet: Bool

    private var isHere: Bool { status == .present || status == .tardy }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(isHere ? Color.black : status == .absent ? Color(.secondaryLabel) : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            .padding(.horizontal, 8)
            .background {
                TileFill(
                    shape: shape,
                    base: TileBase(status: status, quietBackdrop: quiet),
                    isHere: isHere,
                    origin: nil,
                    spread: 1
                )
            }
            .overlay {
                if status == .absent {
                    shape.strokeBorder(
                        Color(quiet ? .tertiaryLabel : .secondaryLabel),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                    )
                } else if !isHere {
                    shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if status == .tardy {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(4)
                }
            }
    }
}
