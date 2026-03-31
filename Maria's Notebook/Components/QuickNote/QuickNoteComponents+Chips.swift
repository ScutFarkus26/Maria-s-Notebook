import SwiftUI

// MARK: - CDLesson Chip

struct QuickNoteLessonChip: View {
    let lessonName: String
    let subject: String
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

            if !subject.isEmpty {
                Text(subject)
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
