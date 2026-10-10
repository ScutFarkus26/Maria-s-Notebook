// TagRename.swift
// Renaming a tag everywhere the shared tag picker's tags are used.

import CoreData

/// The tag picker (`TagPicker`) is shared by todos, todo templates and
/// resources, so renaming a tag in it changes the tag on all three. Note tags
/// are a separate list with their own picker and aren't touched.
enum TagRename {
    /// Renames `original` to `renamed` on every todo, todo template and
    /// resource that has it, without saving. Returns how many rows changed.
    @discardableResult
    static func rename(_ original: String, to renamed: String, in context: NSManagedObjectContext) -> Int {
        guard original != renamed else { return 0 }
        var changed = 0

        func update(_ tags: [String]) -> [String]? {
            guard tags.contains(original) else { return nil }
            changed += 1
            return Self.renamed(original, to: renamed, in: tags)
        }

        for todo in context.safeFetch(withTags(CDTodoItem.self)) {
            if let tags = update(todo.tagsArray) { todo.tagsArray = tags }
        }
        for template in context.safeFetch(withTags(CDTodoTemplate.self)) {
            if let tags = update(template.tagsArray) { template.tagsArray = tags }
        }
        for resource in context.safeFetch(withTags(CDResource.self)) {
            if let tags = update(resource.tagsArray) { resource.tagsArray = tags }
        }
        return changed
    }

    /// `tags` with `original` replaced by `renamed`, keeping each tag once and
    /// the order they were in.
    static func renamed(_ original: String, to renamed: String, in tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0 == original ? renamed : $0 }
            .filter { seen.insert($0).inserted }
    }

    /// Only rows that have any tags; the tag list itself is stored as one
    /// value, so whether it holds this tag is checked after the fetch.
    private static func withTags<T: NSManagedObject>(_ type: T.Type) -> NSFetchRequest<T> {
        let request = CDFetchRequest(type)
        request.predicate = NSPredicate(format: "tags != nil")
        return request
    }
}
