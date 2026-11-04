import Foundation
import CoreData
import UIKit
import Testing
@testable import Daybook_Assistant

// The 2026-11-03 hunt's app-shell fixes (agent Sh): the wallpaper photo,
// the Sample Class's history and the Classroom sheet's reads.
@Suite("Assistant shell fixes 2026-11-03")
@MainActor
struct AssistantFix1103Sh {

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "WallpaperFix1103-\(UUID().uuidString)")
    }

    private static func smallJPEG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    // MARK: - #35: hasPhoto kept, not read from disk on every redraw

    @Test("Whether there's a photo follows Save and Remove, without asking the disk on every read")
    func hasPhotoIsKept() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = AssistantWallpaperPhoto(directory: directory)
        #expect(!photo.hasPhoto)

        try await photo.save(try Self.smallJPEG())
        #expect(photo.hasPhoto)

        // Gone behind its back: the kept answer stands until Remove, so the
        // grid's redraws never look at the disk.
        try FileManager.default.removeItem(at: photo.fileURL)
        #expect(photo.hasPhoto)

        photo.remove()
        #expect(!photo.hasPhoto)
    }

    @Test("A photo saved on an earlier launch is found when the app starts")
    func hasPhotoFromEarlierLaunch() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.smallJPEG().write(to: directory.appending(path: "photo.jpg"))

        let photo = AssistantWallpaperPhoto(directory: directory)
        #expect(photo.hasPhoto)
    }

    // MARK: - #33: the photo decoded ahead, and let go when it isn't chosen

    @Test("With Photo chosen the photo is read ahead of the grid; with another background it isn't")
    func preloadOnlyWhenChosen() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.smallJPEG().write(to: directory.appending(path: "photo.jpg"))
        let photo = AssistantWallpaperPhoto(directory: directory)

        await photo.preload(chosen: AssistantWallpaper.sky.rawValue)
        #expect(photo.image == nil)

        await photo.preload(chosen: AssistantWallpaper.photo.rawValue)
        let image = try #require(photo.image)
        #expect(image.size == CGSize(width: 40, height: 30))
    }

    @Test("The photo is let go once another background is chosen, kept while Photo is, and read again next time")
    func photoLetGoUnlessChosen() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = AssistantWallpaperPhoto(directory: directory)
        try await photo.save(try Self.smallJPEG())

        photo.release(unlessChosen: AssistantWallpaper.photo.rawValue)
        #expect(photo.image != nil)

        photo.release(unlessChosen: AssistantWallpaper.sky.rawValue)
        #expect(photo.image == nil)
        #expect(photo.hasPhoto)
        #expect(AssistantWallpaper.resolved(AssistantWallpaper.photo.rawValue, photoExists: photo.hasPhoto) == .photo)

        photo.loadIfNeeded()
        #expect(photo.image != nil)
    }

    // MARK: - #35: the Sample Class's history from one read of the days off

    @Test("The Sample Class's walk back finds the same school days as stepping one day at a time")
    func sampleWalkMatchesStepping() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let today = try AssistantTestSupport.day("2026-11-03")
        // Days off and a Saturday made a school day, inside the read range
        // and before it, so the walk goes past it too.
        for iso in ["2026-10-30", "2026-10-12", "2026-09-07", "2026-08-20"] {
            let off = CDNonSchoolDay(context: context)
            off.date = try AssistantTestSupport.day(iso)
        }
        for iso in ["2026-10-17", "2026-08-15"] {
            let saturday = CDSchoolDayOverride(context: context)
            saturday.date = try AssistantTestSupport.day(iso)
        }
        try context.save()
        let earliest = try #require(Calendar.current.date(byAdding: .day, value: -40, to: today))
        let daysOff = SchoolDayChecker.nonSchoolDaySet(in: earliest..<today, using: context)

        var stepped = today
        var walked = today
        for _ in 0..<70 {
            let next = SchoolDayChecker.schoolDay(from: stepped, forward: false, using: context)
            let found = AssistantSampleClass.schoolDay(
                before: walked, daysOff: daysOff, from: earliest, using: context
            )
            #expect(found == next)
            guard let next, let found else { break }
            stepped = next
            walked = found
        }
        #expect(stepped < earliest)
    }

    // MARK: - #8, #32: the guide's settings read once

    @Test("The guide's settings read as Classroom and setup read them, nothing set up first")
    func attendanceSendingReads() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let none = AssistantAttendanceSending(in: context)
        #expect(none.dueAt == nil)
        #expect(!none.sendsToParentLocker)
        #expect(AssistantAttendanceSending(in: nil) == none)

        let settings = CDAttendanceEmailSettings(context: context)
        settings.isEnabled = false
        settings.toAddresses = "office@school.org"
        settings.deadlineMinutes = 540
        #expect(context.safeSave())
        #expect(AssistantAttendanceSending(in: context).dueAt == nil)

        settings.isEnabled = true
        #expect(context.safeSave())
        let email = AssistantAttendanceSending(in: context)
        #expect(email.dueAt == FrontDeskEmailReminder.timeString(540))
        #expect(!email.sendsToParentLocker)

        settings.isEnabled = false
        settings.sendMethodRaw = AttendanceSendMethod.parentLocker.rawValue
        settings.deadlineMinutes = 510
        #expect(context.safeSave())
        let parentLocker = AssistantAttendanceSending(in: context)
        #expect(parentLocker.dueAt == FrontDeskEmailReminder.timeString(510))
        #expect(parentLocker.sendsToParentLocker)

        let facts = AssistantClassroomFacts(in: context)
        #expect(facts.sending == parentLocker)
        #expect(facts.joined == nil)
        #expect(facts.classroomID == nil)
    }
}
