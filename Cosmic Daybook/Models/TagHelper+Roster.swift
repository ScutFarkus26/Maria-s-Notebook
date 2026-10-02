// TagHelper+Roster.swift
// A student tag's short name for a view that holds a context but not the roster.

import CoreData
import Foundation

extension TagHelper {
    /// `displayName(_:studentShortNames:)` for a row that has only its
    /// object's context: looks up the student tag's child by exact full name
    /// (one small fetch, student tags only) and falls back to the split when
    /// no student matches. Views that can read `dependencies.roster` pass its
    /// `shortNamesByFullName` instead.
    @MainActor
    static func displayName(_ tag: String, in context: NSManagedObjectContext?) -> String {
        guard let context, let fullName = studentFullName(in: tag) else { return displayName(tag) }
        let firstWord = fullName.split(separator: " ").first.map(String.init) ?? fullName
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "firstName BEGINSWITH %@", firstWord)
        let match = context.safeFetch(request).first { studentNameKey($0.fullName) == fullName }
        guard let match else { return displayName(tag) }
        return displayName(tag, studentShortNames: [fullName: match.shortName])
    }

    /// The same lookup in `object`'s context, for a row holding the record the
    /// tag is on.
    @MainActor
    static func displayName(_ tag: String, contextOf object: NSManagedObject) -> String {
        displayName(tag, in: object.managedObjectContext)
    }
}
