import Foundation

struct StudentsViewModel {
    func filteredStudents(students: [Student], filter: StudentsFilter, sortOrder: SortOrder, today: Date = Date(), presentNowIDs: Set<UUID>? = nil) -> [Student] {
        let base: [Student]
        switch filter {
        case .all:
            base = students
        case .upper:
            base = students.filter { $0.level == .upper }
        case .lower:
            base = students.filter { $0.level == .lower }
        case .presentNow:
            let ids = presentNowIDs ?? []
            base = students.filter { ids.contains($0.id) }
        }

        switch sortOrder {
        case .alphabetical:
            return base.sorted { (lhs: Student, rhs: Student) -> Bool in
                let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                if nameOrder == .orderedSame { return lhs.manualOrder < rhs.manualOrder }
                return nameOrder == .orderedAscending
            }
        case .age:
            // Sort by birthday (younger first): later birthday comes first
            return base.sorted { (lhs: Student, rhs: Student) -> Bool in
                if lhs.birthday == rhs.birthday { return lhs.manualOrder < rhs.manualOrder }
                return lhs.birthday > rhs.birthday
            }
        case .birthday:
            let todayStart = Calendar.current.startOfDay(for: today)
            return base.sorted { (lhs: Student, rhs: Student) -> Bool in
                let l = nextBirthday(from: lhs.birthday, relativeTo: todayStart)
                let r = nextBirthday(from: rhs.birthday, relativeTo: todayStart)
                if l == r { return lhs.manualOrder < rhs.manualOrder }
                return l < r
            }
        case .lastLesson:
            return base.sorted { lhs, rhs in
                let l = daysSinceLastLesson(for: lhs)
                let r = daysSinceLastLesson(for: rhs)
                if l != r { return l > r } // largest first
                let nameOrder = lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName)
                if nameOrder == .orderedSame { return lhs.manualOrder < rhs.manualOrder }
                return nameOrder == .orderedAscending
            }
        case .manual:
            return base.sorted { $0.manualOrder < $1.manualOrder }
        }
    }

    func ensureInitialManualOrderIfNeeded(_ students: [Student]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        let allZero = all.allSatisfy { $0.manualOrder == 0 }
        if allZero {
            let sorted = all.sorted { (lhs: Student, rhs: Student) -> Bool in
                lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
            var changed = false
            for (idx, s) in sorted.enumerated() {
                if s.manualOrder != idx { s.manualOrder = idx; changed = true }
            }
            return changed
        }
        return false
    }

    func repairManualOrderUniquenessIfNeeded(_ students: [Student]) -> Bool {
        let all = students
        guard !all.isEmpty else { return false }
        var seen = Set<Int>()
        var duplicates: [Student] = []
        // Keep first occurrence of each order and collect duplicates (e.g., newly added with default 0)
        for s in all.sorted(by: { $0.manualOrder < $1.manualOrder }) {
            if seen.contains(s.manualOrder) {
                duplicates.append(s)
            } else {
                seen.insert(s.manualOrder)
            }
        }
        if !duplicates.isEmpty {
            var maxOrder = seen.max() ?? -1
            for s in duplicates {
                maxOrder += 1
                if s.manualOrder != maxOrder { s.manualOrder = maxOrder }
            }
            return true
        }
        return false
    }

    func mergeReorderedSubsetIntoAll(movingID: UUID, from fromIndex: Int, to toIndex: Int, current: [Student], allStudents: [Student]) -> [UUID] {
        // Full list ordered by current manualOrder
        let allOrdered = allStudents.sorted { $0.manualOrder < $1.manualOrder }

        // IDs of the currently visible (filtered) subset
        let subsetIDs = current.map { $0.id }
        var subset = subsetIDs
        // Reorder within the subset
        if let sFrom = subset.firstIndex(of: movingID) {
            let item = subset.remove(at: sFrom)
            let boundedIndex = max(0, min(subset.count, toIndex))
            subset.insert(item, at: boundedIndex)
        }

        // Merge: replace the positions of subset items in the full list with the new subset order
        let subsetSet = Set(subsetIDs)
        var subsetQueue = subset
        var newAllIDs: [UUID] = []
        for s in allOrdered {
            if subsetSet.contains(s.id) {
                // Take next from the reordered subset
                if !subsetQueue.isEmpty {
                    newAllIDs.append(subsetQueue.removeFirst())
                }
            } else {
                newAllIDs.append(s.id)
            }
        }
        return newAllIDs
    }

    // MARK: - Helpers
    private func nextBirthday(from birthday: Date, relativeTo today: Date = Date()) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let comps = cal.dateComponents([.month, .day], from: birthday)
        guard let month = comps.month, let day = comps.day else { return .distantFuture }

        var year = cal.component(.year, from: todayStart)
        var thisYearComponents = DateComponents(year: year, month: month, day: day)
        var thisYearDate = cal.date(from: thisYearComponents)
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYearDate == nil && month == 2 && day == 29 {
            thisYearComponents.day = 28
            thisYearDate = cal.date(from: thisYearComponents)
        }
        guard let thisYear = thisYearDate else { return .distantFuture }

        if thisYear >= todayStart {
            return thisYear
        } else {
            year += 1
            var nextComponents = DateComponents(year: year, month: month, day: day)
            var nextDate = cal.date(from: nextComponents)
            if nextDate == nil && month == 2 && day == 29 {
                nextComponents.day = 28
                nextDate = cal.date(from: nextComponents)
            }
            return nextDate ?? thisYear
        }
    }

    private func daysSinceLastLesson(for student: Student) -> Int {
        // Use the student's in-memory lessons list if populated; otherwise, return 0.
        // This helper is a fallback used only when the view cannot provide context-aware counts.
        var last: Date? = nil
        for sl in student.studentLessons {
            if sl.isGiven {
                let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
                if let current = last {
                    if when > current { last = when }
                } else {
                    last = when
                }
            }
        }
        guard let lastDate = last else { return 0 }
        // Approximate school days by excluding weekends only (no context available here).
        let cal = Calendar.current
        let start = cal.startOfDay(for: lastDate)
        let end = cal.startOfDay(for: Date())
        if end <= start { return 0 }
        var count = 0
        var cursor = start
        while cursor < end {
            let wd = cal.component(.weekday, from: cursor)
            if wd != 1 && wd != 7 { count += 1 }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return max(0, count)
    }
}

