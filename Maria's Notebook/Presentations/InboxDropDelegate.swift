import SwiftUI
import SwiftData
import OSLog
import UniformTypeIdentifiers

// MARK: - Drop Delegate for Inbox

struct PresentationsInboxDropDelegate: DropDelegate {
    private static let logger = Logger.presentations
    let modelContext: ModelContext
    let lessonAssignments: [LessonAssignment]
    let coordinator: PresentationsCoordinator

    func dropEntered(info: DropInfo) {
        adaptiveWithAnimation { coordinator.setInboxTargeted(true) }
    }

    func dropExited(info: DropInfo) {
        adaptiveWithAnimation { coordinator.setInboxTargeted(false) }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        adaptiveWithAnimation { coordinator.setInboxTargeted(false) }
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let str = reading as? String,
                  let payload = UnifiedCalendarDragPayload.parse(str),
                  case .presentation(let id) = payload else { return }

            Task { @MainActor in
                if let la = lessonAssignments.first(where: { $0.id == id }) {
                    if la.scheduledFor != nil {
                        la.unschedule()
                        do {
                            try modelContext.save()
                        } catch {
                            Self.logger.warning("Presentations inbox unschedule save failed: \(error)")
                        }
                    }
                }
            }
        }
        return true
    }
}
