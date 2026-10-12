//
//  DataCleanupService+LessonLinks.swift
//  Cosmic Daybook
//
//  The lesson ids other records keep as text — singly, in comma-separated
//  lists, or as the keys of a JSON object — moved from a lesson the name
//  merge folds onto the one it keeps (`mergeSameNameLessons`). Going Out
//  curriculum links and story match reasons were left pointing at the
//  deleted lesson until the 2026-10-12 bug hunt (#3).
//

import CoreData
import Foundation

nonisolated extension DataCleanupService {

    /// The lesson-to-lesson, resource, story and Going Out links.
    static func repointLessonLinks(from oldID: String, to newID: String, in context: NSManagedObjectContext) {
        for lesson in fetch(CDLesson.self, where: "derivedFromLessonID == %@", oldID, in: context) {
            lesson.derivedFromLessonID = newID
        }
        for lesson in fetch(CDLesson.self, where: "parentStoryID == %@", oldID, in: context) {
            lesson.parentStoryID = newID
        }
        for lesson in fetch(CDLesson.self, where: "prerequisiteLessonIDs CONTAINS %@", oldID, in: context) {
            lesson.prerequisiteLessonIDs = replacing(oldID, with: newID, inList: lesson.prerequisiteLessonIDs)
        }
        for lesson in fetch(CDLesson.self, where: "relatedLessonIDs CONTAINS %@", oldID, in: context) {
            lesson.relatedLessonIDs = replacing(oldID, with: newID, inList: lesson.relatedLessonIDs)
        }
        for resource in fetch(CDResource.self, where: "linkedLessonIDs CONTAINS %@", oldID, in: context) {
            resource.linkedLessonIDs = replacing(oldID, with: newID, inList: resource.linkedLessonIDs)
        }
        for story in fetch(CDStory.self, where: "relatedLessonIDsRaw CONTAINS %@", oldID, in: context) {
            story.relatedLessonIDsRaw = replacing(oldID, with: newID, inList: story.relatedLessonIDsRaw)
        }
        for story in fetch(CDStory.self, where: "relatedLessonReasonsJSON CONTAINS[c] %@", oldID, in: context) {
            story.relatedLessonReasonsJSON = movingReason(from: oldID, to: newID, in: story.relatedLessonReasonsJSON)
        }
        for trip in fetch(CDGoingOut.self, where: "curriculumLinkIDs CONTAINS[c] %@", oldID, in: context) {
            trip.curriculumLinkIDs = replacing(oldID, with: newID, inList: trip.curriculumLinkIDs)
        }
    }

    /// Rewrites one id in a comma-separated id list, dropping the double that
    /// results when both ids were already listed.
    static func replacing(_ old: String, with new: String, inList list: String) -> String {
        var seen: Set<String> = []
        var kept: [String] = []
        for piece in list.split(separator: ",") {
            let trimmed: String = String(piece).trimmed()
            if trimmed.isEmpty { continue }
            let isOld: Bool = trimmed.caseInsensitiveCompare(old) == .orderedSame
            let id: String = isOld ? new : trimmed
            if seen.insert(id.uppercased()).inserted { kept.append(id) }
        }
        return kept.joined(separator: ",")
    }

    /// A story's match reasons (`CDStory.relatedLessonReasons`, keyed by lesson
    /// id) with the folded lesson's reason under the kept lesson's id. When
    /// both lessons were matched, the kept lesson's own reason stays. JSON this
    /// can't read is left as it is.
    static func movingReason(from oldID: String, to newID: String, in json: String) -> String {
        guard let data = json.data(using: .utf8),
              var reasons = try? JSONDecoder().decode([String: String].self, from: data),
              let oldKey = reasons.keys.first(where: { $0.caseInsensitiveCompare(oldID) == .orderedSame }),
              let reason = reasons.removeValue(forKey: oldKey)
        else { return json }
        let keptKey = reasons.keys.first { $0.caseInsensitiveCompare(newID) == .orderedSame } ?? newID
        if (reasons[keptKey] ?? "").trimmed().isEmpty { reasons[keptKey] = reason }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let encoded = try? encoder.encode(reasons), let text = String(data: encoded, encoding: .utf8) else {
            return json
        }
        return text
    }

    private static func fetch<T: NSManagedObject>(
        _ type: T.Type, where format: String, _ argument: String, in context: NSManagedObjectContext
    ) -> [T] {
        let request = CDFetchRequest(T.self)
        request.predicate = NSPredicate(format: format, argument)
        return context.safeFetch(request).filter { !$0.isDeleted }
    }
}
