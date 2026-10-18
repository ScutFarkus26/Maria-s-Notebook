import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17: a meeting- or note-template delete whose save failed
/// looked done and stayed pending in the context, to be saved by whatever
/// saved next (#42); and the meeting-template editor wouldn't save without
/// all four prompts, which the built-in Quick Check-In doesn't have (#44).
@Suite("Templates (fix 10-17 St)")
@MainActor
struct TemplateFix1017StTests {

    /// Another screen's unsaved row that can't be saved, so the next save fails.
    private func blockSaves(in context: NSManagedObjectContext) {
        let unsaveable = CDWorkModel(context: context)
        unsaveable.setValue(nil, forKey: "title")
    }

    private func isGone(_ object: NSManagedObject) -> Bool {
        object.isDeleted || object.managedObjectContext == nil
    }

    // MARK: - #42 Deletes

    @Test("A meeting-template delete that can't be saved is taken back, active template and all")
    func failedMeetingTemplateDeleteIsTakenBack() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let builtIn = CDMeetingTemplate(context: context)
        builtIn.name = "Weekly"
        builtIn.isBuiltIn = true
        let custom = CDMeetingTemplate(context: context)
        custom.name = "Mine"
        custom.isActive = true
        #expect(CoreDataTestHelpers.save(context))
        blockSaves(in: context)

        let deleted = MeetingTemplateManaging.delete(custom, in: context, saveCoordinator: SaveCoordinator())

        #expect(!deleted)
        #expect(!isGone(custom))
        #expect(!context.deletedObjects.contains(custom))
        #expect(custom.isActive)
        #expect(!builtIn.isActive)
    }

    @Test("A note-template delete that can't be saved is taken back")
    func failedNoteTemplateDeleteIsTakenBack() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let custom = CDNoteTemplate(context: context)
        custom.title = "Mine"
        #expect(CoreDataTestHelpers.save(context))
        blockSaves(in: context)

        let deleted = NoteTemplateManaging.delete(custom, in: context, saveCoordinator: SaveCoordinator())

        #expect(!deleted)
        #expect(!isGone(custom))
        #expect(!context.deletedObjects.contains(custom))
    }

    @Test("A template delete that saves is done, and hands the active mark to a built-in one")
    func savedDeleteIsDone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let builtIn = CDMeetingTemplate(context: context)
        builtIn.name = "Weekly"
        builtIn.isBuiltIn = true
        let custom = CDMeetingTemplate(context: context)
        custom.name = "Mine"
        custom.isActive = true
        let note = CDNoteTemplate(context: context)
        note.title = "Mine"
        #expect(CoreDataTestHelpers.save(context))

        #expect(MeetingTemplateManaging.delete(custom, in: context, saveCoordinator: SaveCoordinator()))
        #expect(NoteTemplateManaging.delete(note, in: context, saveCoordinator: SaveCoordinator()))

        #expect(isGone(custom))
        #expect(isGone(note))
        #expect(builtIn.isActive)
        #expect(!context.hasChanges)
    }

    // MARK: - #44 Meeting-template editor

    @Test("A meeting template needs a name; its prompts are optional")
    func meetingTemplateNeedsOnlyAName() {
        #expect(MeetingTemplateEditing.canSave(MeetingTemplateDraft(name: "Quick Check-In")))
        #expect(MeetingTemplateEditing.canSave(
            MeetingTemplateDraft(name: "Quick Check-In", reflectionPrompt: "How was your week?")
        ))
        #expect(!MeetingTemplateEditing.canSave(MeetingTemplateDraft(name: "  ", reflectionPrompt: "How was it?")))
    }
}
