import SwiftUI

// MARK: - Photo Loading Line

/// Shown while a picked photo is still on its way (an iCloud Photos original
/// can take seconds); Save waits for it. Remove stops the wait, so a photo
/// that never comes doesn't hold Save and her note.
struct QuickNotePhotoLoadingLine: View {
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Adding photo…")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button("Remove", action: onRemove)
                .font(AppTheme.ScaledFont.caption)
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove photo")
        }
    }
}

/// Why a picked photo wasn't added (it took too long to arrive).
struct QuickNotePhotoMessageLine: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - CDLesson Chip

struct QuickNoteLessonChip: View {
    let lessonName: String
    let area: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: SFSymbol.Education.book)
                .font(.system(size: 12))
                .foregroundStyle(.indigo)

            Text(lessonName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            if !area.isEmpty {
                Text(area)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Color.indigo.opacity(UIConstants.OpacityConstants.light))
        .clipShape(Capsule())
    }
}

// MARK: - Camera View (iOS only)

#if !os(macOS)
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onCapture: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            parent.image = image
            parent.onCapture(image)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
