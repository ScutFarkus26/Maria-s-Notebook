// EntityWindowHost.swift
// The shell every detail window shares.
//
// A window scene is handed an id, not an object, so each host began the same
// way: look the row up in the view context, draw it at a minimum size the
// window is usable at, and — because another window may have deleted it in the
// meantime — say so plainly when it is gone. That shell is here once; what is
// left in each host is the part that is actually about that record.

import CoreData
import SwiftUI

/// The placeholder a window shows when its record has gone.
struct WindowHostNotFound {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text?
    /// Minimum window size while the placeholder is up; `nil` leaves the size
    /// to the scene.
    let minSize: CGSize?

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil,
        minSize: CGSize? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.minSize = minSize
    }
}

/// Resolves `id` to an `Entity` in the view context and hands it to `content`,
/// falling back to `notFound` when the row is no longer there.
struct EntityWindowHost<Entity: NSManagedObject, Content: View>: View {
    private let id: UUID
    private let minSize: CGSize?
    private let notFound: WindowHostNotFound
    private let content: (Entity) -> Content

    @Environment(\.managedObjectContext) private var viewContext

    init(
        id: UUID,
        minSize: CGSize? = nil,
        notFound: WindowHostNotFound,
        @ViewBuilder content: @escaping (Entity) -> Content
    ) {
        self.id = id
        self.minSize = minSize
        self.notFound = notFound
        self.content = content
    }

    var body: some View {
        if let entity = viewContext.object(Entity.self, id: id) {
            content(entity)
                .windowMinSize(minSize)
        } else {
            ContentUnavailableView(
                notFound.title,
                systemImage: notFound.systemImage,
                description: notFound.description
            )
            .windowMinSize(notFound.minSize)
        }
    }
}

private extension View {
    /// `nil` means "no minimum" — several windows deliberately leave sizing to
    /// the scene.
    @ViewBuilder
    func windowMinSize(_ size: CGSize?) -> some View {
        if let size {
            frame(minWidth: size.width, minHeight: size.height)
        } else {
            self
        }
    }
}
