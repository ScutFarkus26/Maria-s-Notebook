import Foundation

/// The app's one Core Data stack. Siri can run an attendance command with no
/// window open, before `AssistantBootstrapper` has started, and a second
/// `NSPersistentCloudKitContainer` on the same store files would fight the
/// first over sync; so whichever gets here first builds it, and the other
/// gets the same one.
@MainActor
enum AssistantStack {
    private static var stack: CoreDataStack?

    static func shared() throws -> CoreDataStack {
        if let stack { return stack }
        let made: CoreDataStack
        #if DEBUG
        if AssistantSampleClass.isRequested {
            made = try AssistantSampleClass.makeStack()
        } else {
            made = try CoreDataStack()
        }
        #else
        made = try CoreDataStack()
        #endif
        stack = made
        return made
    }
}
