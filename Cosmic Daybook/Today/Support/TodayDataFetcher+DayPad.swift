import CoreData
import Foundation
import OSLog

extension TodayDataFetcher {

    // MARK: - Day Pad Fetching

    /// Fetches the day pad for a specific date, if one exists.
    ///
    /// Two devices that each start the day's pad before they sync leave two
    /// rows for one day. They are joined, never dropped: the pad that sorts
    /// first by `createdAt`, then `id`, is kept (the same one on every device,
    /// so devices joining at once converge), each other pad's text is added to
    /// it in that order, after a blank line, unless the kept pad already
    /// contains it, and the others are deleted. The join is left unsaved; the
    /// caller saves it (`context.hasChanges`). The MCP `day_pad` tool reads
    /// through here too.
    static func fetchDayPad(
        day: Date,
        context: NSManagedObjectContext
    ) -> CDDayPad? {
        let dayStart = AppCalendar.startOfDay(day)
        let request = CDFetchRequest(CDDayPad.self)
        request.predicate = NSPredicate(format: "day == %@", dayStart as NSDate)
        do {
            let pads = try context.fetch(request).filter { !$0.isDeleted }
            guard pads.count > 1 else { return pads.first }
            return joinDuplicatePads(pads, in: context)
        } catch {
            Logger.app_.error("Error fetching day pad: \(error)")
            return nil
        }
    }

    /// Joins one day's pads into the first by `createdAt`, then `id`, and
    /// deletes the rest. See `fetchDayPad`.
    static func joinDuplicatePads(_ pads: [CDDayPad], in context: NSManagedObjectContext) -> CDDayPad? {
        let ordered = joinOrder(pads)
        guard let kept = ordered.first else { return nil }
        let body = joinedText(of: ordered)
        for other in ordered.dropFirst() {
            context.delete(other)
        }
        kept.setBody(body)
        return kept
    }

    /// One day's pads in the order a join takes them: by `createdAt`, then
    /// `id`, so every device keeps the same one.
    static func joinOrder(_ pads: [CDDayPad]) -> [CDDayPad] {
        pads.sorted { lhs, rhs in
            let left = lhs.createdAt ?? .distantPast
            let right = rhs.createdAt ?? .distantPast
            if left != right { return left < right }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    /// The text a join leaves in the kept pad (`ordered`'s first): its own
    /// text, then each other pad's, after a blank line, unless already there.
    /// Changes nothing, so a screen can show what a join would keep.
    static func joinedText(of ordered: [CDDayPad]) -> String {
        guard let kept = ordered.first else { return "" }
        var body = kept.body ?? ""
        for other in ordered.dropFirst() {
            let text = (other.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !body.contains(text) {
                body = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : body + "\n\n" + text
            }
        }
        return body
    }

    /// The day's pad text as a join would leave it, without joining: for
    /// readers that must not write, such as the Claude tool `schedule_for_range`.
    /// Empty when the day has no pad.
    static func padText(day: Date, context: NSManagedObjectContext) -> String {
        let request = CDFetchRequest(CDDayPad.self)
        request.predicate = NSPredicate(format: "day == %@", AppCalendar.startOfDay(day) as NSDate)
        let pads = context.safeFetch(request).filter { !$0.isDeleted }
        return joinedText(of: joinOrder(pads))
    }

    // MARK: - Adding to a Pad

    /// Adds `text`, trimmed, to the end of the day's pad as a paragraph of its
    /// own (after a blank line), making the pad when the day has none. Joins
    /// the day's copies first (`fetchDayPad`). Whether the text is already
    /// there is the caller's call. Returns the pad, or nil for empty text.
    /// Doesn't save the context.
    @discardableResult
    static func appendPadText(_ text: String, day: Date, context: NSManagedObjectContext) -> CDDayPad? {
        let addition = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return nil }
        let dayStart = AppCalendar.startOfDay(day)
        let pad = fetchDayPad(day: dayStart, context: context) ?? CDDayPad(context: context, day: dayStart)
        let stored = pad.body ?? ""
        let storedText = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        pad.setBody(storedText.isEmpty ? addition : stored + "\n\n" + addition)
        return pad
    }

    // MARK: - Saving From an Open Editor

    /// What an editor's save wrote: the day's pad (nil when there is still no
    /// text at all) and the text it now holds, to show in the editor.
    struct SavedDayPad {
        let pad: CDDayPad?
        let text: String
    }

    /// Saves what she typed into the day's pad, looking the pad up again first
    /// (and joining copies), since an editor stays open for hours: another
    /// device may have joined its pad into this one, deleted the copy the
    /// editor holds, or written a pad for a day the editor opened empty.
    /// `base` is the pad's text as the editor last loaded or saved it; when the
    /// stored text has moved on from it, her typing is added to the stored
    /// text (`mergedPadText`) rather than written over it. Doesn't save the
    /// context.
    static func savePadText(
        _ typed: String, base: String, day: Date, context: NSManagedObjectContext
    ) -> SavedDayPad {
        let dayStart = AppCalendar.startOfDay(day)
        let current = fetchDayPad(day: dayStart, context: context)
        let text = mergedPadText(typed: typed, base: base, stored: current?.body ?? "")
        guard let pad = current ?? (text.isEmpty ? nil : CDDayPad(context: context, day: dayStart)) else {
            return SavedDayPad(pad: nil, text: text)
        }
        pad.setBody(text)
        return SavedDayPad(pad: pad, text: text)
    }

    /// The text to save when the editor started from `base`, she now has
    /// `typed`, and the store holds `stored`. Unchanged underneath: her text.
    /// Changed underneath: the stored text, then what she added after `base`
    /// (or all she has, if she edited inside it), after a blank line, unless
    /// the stored text already contains it.
    ///
    /// The three are compared with the spacing at their ends trimmed. The
    /// Calendar's field saves her text trimmed, while the pad it opened on
    /// can end with a line break: compared as they were, her addition read as
    /// an edit inside the pad, and the whole pad went in again after itself;
    /// so did a stored text that differed only by that line break.
    static func mergedPadText(typed: String, base: String, stored: String) -> String {
        let typedText = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseText = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stored.trimmingCharacters(in: .whitespacesAndNewlines) != baseText else { return typed }
        guard typedText != baseText, !stored.contains(typedText) else { return stored }
        let added: Substring
        if typed.hasPrefix(base) {
            added = typed.dropFirst(base.count)
        } else if typedText.hasPrefix(baseText) {
            added = typedText.dropFirst(baseText.count)
        } else {
            added = Substring(typed)
        }
        let addition = added.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty, !stored.contains(addition) else { return stored }
        let storedText = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return storedText.isEmpty ? addition : stored + "\n\n" + addition
    }
}
