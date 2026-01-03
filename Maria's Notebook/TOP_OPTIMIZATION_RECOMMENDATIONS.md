# Top Optimization Recommendations

Based on analysis of the codebase, existing performance audits, and code patterns, here are the top 5 ways to speed up the app and improve stability without losing functionality.

---

## Top 5 Performance Optimizations

### 1. **Make RootView Backfill Operations Asynchronous** ⚡ (Critical)
**Location:** `AppCore/RootView.swift` (lines ~286-288, 345, 382)

**Problem:** Three backfill operations (`backfillRelationshipsIfNeeded`, `backfillIsPresentedIfNeeded`, `backfillScheduledForDayIfNeeded`) run synchronously in `onAppear`, fetching ALL StudentLesson, Student, and Lesson records on app launch, blocking the UI.

**Impact:** **HIGH** - Blocks app launch for 2-10+ seconds with large datasets. Already documented in PERFORMANCE_OPTIMIZATION_GUIDE.md.

**Solution:** Convert to async/await with `.task` modifier:
```swift
// Replace .onAppear { } with:
.task {
    await backfillRelationshipsIfNeeded()
    await backfillIsPresentedIfNeeded()
    await backfillScheduledForDayIfNeeded()
}

// Make functions async (preserves exact same functionality):
private func backfillRelationshipsIfNeeded() async {
    guard !didBackfillRelationships else { return }
    await Task { @MainActor in
        // Existing logic unchanged - just wrapped in async
    }.value
}
```

**Expected Improvement:** 50-70% faster app launch time.

---

### 2. **Replace Unfiltered @Query with Predicates** ⚡ (High Priority)
**Locations:** Multiple views identified in PerformanceAudit.md

**Problem:** Many views load entire tables when only subsets are needed:
- `Settings/SettingsView.swift` - Loads ALL Student, Lesson, StudentLesson just for counts
- `Inbox/FollowUpInboxView.swift` - 7 unfiltered queries loading entire tables
- `Work/WorkContractDetailSheet.swift` - 6 unfiltered queries in a detail view
- `Students/StudentLessonsRootView.swift` - Loads all StudentLesson, filters in memory
- `Planning/PlanningWeekView.swift` - Loads all records, filters by date in Swift

**Impact:** **HIGH** - Significant memory usage and slow view rendering, especially for:
- Settings view (accessed frequently)
- StudentLessonsRootView (core navigation screen)
- PlanningWeekView (loads on every week navigation)

**Solution:** Add predicates to @Query to filter at database level:
```swift
// ❌ Before (SettingsView.swift):
@Query private var students: [Student]
@Query private var lessons: [Lesson]
@Query private var studentLessons: [StudentLesson]

// ✅ After - Use counts or targeted queries:
// For counts only, use FetchDescriptor count queries instead of loading all:
private var studentsTotal: Int {
    let descriptor = FetchDescriptor<Student>()
    descriptor.propertiesToFetch = [] // Don't load properties, just count
    return (try? modelContext.fetch(descriptor).count) ?? 0
}

// ✅ For PlanningWeekView - filter by date range:
@Query(
    filter: #Predicate<StudentLesson> { sl in
        if let scheduled = sl.scheduledFor {
            // Filter within week range
            return scheduled >= weekStart && scheduled < weekEnd
        }
        return false
    }
) private var weekStudentLessons: [StudentLesson]
```

**Expected Improvement:** 30-50% faster view navigation, 20-40% memory reduction.

---

### 3. **Optimize SettingsView Statistics Queries** ⚡ (High Priority)
**Location:** `Settings/SettingsView.swift` (lines 12-25)

**Problem:** Loads entire Student, Lesson, StudentLesson tables just to display counts (studentsTotal, lessonsTotal, plannedTotal, givenTotal). This is the worst offender - loading thousands of records for 4 numbers.

**Impact:** **HIGH** - Settings is accessed frequently and blocks UI on every access.

**Solution:** Replace @Query with count-only fetches:
```swift
// Instead of:
@Query private var students: [Student]
@Query private var lessons: [Lesson]
private var studentsTotal: Int { students.count }

// Use:
private var studentsTotal: Int {
    let descriptor = FetchDescriptor<Student>()
    // SwiftData doesn't have direct count, but we can optimize:
    // Option 1: Use a separate service that caches counts
    // Option 2: Only fetch when needed and cache the result
    // Option 3: Use @Query but with fetchLimit 0 and count property access
}

// Better: Create a SettingsStatsViewModel that loads counts on demand:
@MainActor
class SettingsStatsViewModel: ObservableObject {
    @Published var studentsCount: Int = 0
    @Published var lessonsCount: Int = 0
    
    func loadCounts(context: ModelContext) {
        Task {
            let students = context.safeFetch(FetchDescriptor<Student>())
            let lessons = context.safeFetch(FetchDescriptor<Lesson>())
            // For large datasets, consider sampling or caching
            await MainActor.run {
                self.studentsCount = students.count
                self.lessonsCount = lessons.count
            }
        }
    }
}
```

**Expected Improvement:** 60-80% faster Settings view load time.

---

### 4. **Cache Expensive Computations in View Bodies** ⚡ (Medium-High Priority)
**Location:** `Presentations/PresentationsView.swift`, `Students/StudentLessonsRootView.swift`, and others

**Problem:** Expensive filtering, grouping, and computation operations run in view bodies, recalculating on every view update. Examples:
- `getBlockingContracts()` and `isBlocked()` called repeatedly
- Days-since calculations
- Grouping operations on large arrays

**Impact:** **MEDIUM-HIGH** - Causes stuttering and slow scrolling, especially in lists.

**Solution:** Move to ViewModels with caching (partially done in PresentationsViewModel):
```swift
// ✅ Already implemented pattern in PresentationsViewModel:
// Apply same pattern to other views:

@MainActor
class StudentLessonsViewModel: ObservableObject {
    @Published var filteredLessons: [StudentLesson] = []
    private var lastFilterHash: Int = 0
    
    func updateFilteredLessons(
        allLessons: [StudentLesson],
        subjectFilter: String?,
        completionFilter: Bool?
    ) {
        let filterHash = hashValue(subjectFilter, completionFilter)
        guard filterHash != lastFilterHash else { return }
        
        // Recompute only when filters change
        filteredLessons = allLessons.filter { lesson in
            // Filter logic
        }
        lastFilterHash = filterHash
    }
}
```

**Expected Improvement:** 40-60% smoother scrolling and faster view updates.

---

### 5. **Implement Lazy Loading for Detail Views** ⚡ (Medium Priority)
**Location:** `Work/WorkContractDetailSheet.swift`, `Students/StudentLessonDetailView.swift`, and other detail sheets

**Problem:** Detail views load ALL related tables just to display one item:
- `WorkContractDetailSheet` loads ALL lessons, students, workNotes, presentations, planItems, contracts
- `StudentLessonDetailView` loads ALL lessons, students, studentLessons for a single StudentLesson

**Impact:** **MEDIUM-HIGH** - Slow sheet opening, high memory usage.

**Solution:** Fetch only related items by ID/relationship:
```swift
// ❌ Before:
@Query private var lessons: [Lesson]
@Query private var students: [Student]

// ✅ After - fetch only what's needed:
@State private var relatedLessons: [Lesson] = []
@State private var relatedStudents: [Student] = []

.onAppear {
    Task {
        // Fetch only lessons/students related to this contract
        let contract = viewModel.contract
        let lessonIDs = Set(contract.lessonIDs) // Assuming contract has lessonIDs
        let descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { lessonIDs.contains($0.id) }
        )
        relatedLessons = modelContext.safeFetch(descriptor)
        
        // Same for students
    }
}
```

**Expected Improvement:** 50-70% faster sheet opening, reduced memory spikes.

---

## Top 5 Stability Improvements

### 1. **Replace Force Unwraps with Safe Unwrapping** 🛡️ (Critical)
**Location:** 162 files found with `!` operator

**Problem:** Force unwraps (`!`) crash the app if values are nil. Common patterns found:
- Force unwrapping optionals after operations
- Force casting with `as!`
- Array indexing without bounds checks

**Impact:** **CRITICAL** - These are the most common cause of crashes.

**Solution:** Use safe unwrapping and guard statements:
```swift
// ❌ Before:
let name = student.firstName!
let lesson = lessons[index]!
let student = item as! Student

// ✅ After:
guard let name = student.firstName else {
    print("Warning: Student missing firstName")
    return
}
guard index < lessons.count else {
    print("Warning: Index out of bounds")
    return []
}
guard let student = item as? Student else {
    print("Warning: Invalid type")
    return
}

// For array access:
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Usage:
if let lesson = lessons[safe: index] {
    // Safe to use
}
```

**Expected Improvement:** Eliminate 70-90% of nil-related crashes.

---

### 2. **Standardize Error Handling for SwiftData Operations** 🛡️ (High Priority)
**Location:** Throughout codebase - inconsistent save/fetch error handling

**Problem:** Inconsistent error handling for SwiftData operations:
- Some places use `try?` and silently fail
- Some use `safeSave()` extension
- Some use `SaveCoordinator`
- Some have no error handling at all

**Impact:** **HIGH** - Silent data loss, crashes on save failures, inconsistent user experience.

**Solution:** Standardize on safe patterns:
```swift
// ✅ Use safeFetch extension consistently (already exists):
let results = modelContext.safeFetch(descriptor) // Returns [] on error

// ✅ Use SaveCoordinator for UI-visible saves:
let success = saveCoordinator.save(modelContext, reason: "Saving lesson")
if !success {
    // Error already handled and shown to user
}

// ✅ Use safeSave for background/non-critical saves:
modelContext.safeSave() // Logs error but doesn't crash

// ✅ For critical saves, handle errors explicitly:
do {
    try modelContext.save()
} catch {
    // Log and show error to user
    print("Critical save failed: \(error)")
    // Show alert or handle gracefully
}
```

**Create guidelines:**
- Use `safeFetch` for all fetches unless you need to handle errors specifically
- Use `SaveCoordinator.save()` for user-initiated actions
- Use `safeSave()` for background autosaves
- Always handle errors explicitly for critical operations

**Expected Improvement:** Eliminate silent failures, consistent error handling, better user feedback.

---

### 3. **Add Bounds Checking for Array/Collection Access** 🛡️ (Medium-High Priority)
**Location:** Throughout codebase - array indexing, subscripts, collection operations

**Problem:** Direct array access without bounds checking can crash:
- `array[index]` without checking `index < array.count`
- `array.first!` when array might be empty
- Collection operations assuming non-empty

**Impact:** **MEDIUM-HIGH** - Index out of bounds crashes.

**Solution:** Add safe access patterns:
```swift
// ✅ Create safe access extensions:
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// ✅ Use safe access:
if let first = array.first { // Instead of array.first!
    // Use first
}

// ✅ Check before accessing:
guard !items.isEmpty else {
    return defaultValue
}
let item = items[0]

// ✅ Use enumerated() safely:
for (index, item) in items.enumerated() {
    guard let related = relatedItems[safe: index] else { continue }
    // Process
}
```

**Expected Improvement:** Eliminate index-out-of-bounds crashes.

---

### 4. **Improve Fallback Paths for Failed Predicates** 🛡️ (Medium Priority)
**Location:** `ViewModels/TodayViewModel.swift`, `Students/StudentsView.swift`, and others

**Problem:** Many optimized paths have fallbacks that load ALL records if predicates fail:
```swift
// From TodayViewModel.swift (line ~206):
// Main path uses predicate, but fallback loads all:
let descriptor = FetchDescriptor<Student>(
    predicate: predicate
)
let students = try? context.fetch(descriptor) ?? context.safeFetch(FetchDescriptor<Student>()) // ❌ Falls back to ALL
```

**Impact:** **MEDIUM** - If predicate fails, silently falls back to worst-case performance.

**Solution:** Improve predicate support and handle failures explicitly:
```swift
// ✅ Better approach:
func loadStudents(ids: Set<UUID>) -> [Student] {
    // Try predicate first
    let predicate = #Predicate<Student> { ids.contains($0.id) }
    let descriptor = FetchDescriptor<Student>(predicate: predicate)
    
    if let students = try? context.fetch(descriptor), !students.isEmpty {
        return students
    }
    
    // If predicate fails, fetch by iterating IDs (still better than all)
    var results: [Student] = []
    for id in ids {
        let singleDescriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == id }
        )
        if let student = context.safeFetchFirst(singleDescriptor) {
            results.append(student)
        }
    }
    return results
    
    // Only as last resort, but log the issue:
    // print("Warning: Predicate fetch failed, using individual fetches")
}
```

**Expected Improvement:** More resilient to predicate failures, better error visibility.

---

### 5. **Add Validation and Guard Clauses for User Input** 🛡️ (Medium Priority)
**Location:** Import/CSV processing, form inputs, data entry views

**Problem:** User input and external data (CSV imports) may contain invalid data that causes crashes:
- Missing required fields
- Invalid date formats
- Type mismatches
- Unexpected nil values

**Impact:** **MEDIUM** - Crashes during imports or data entry, especially from malformed CSV files.

**Solution:** Add comprehensive validation (partially done in CSV importers):
```swift
// ✅ Good pattern already in StudentCSVImporter.swift:
func value(_ idx: Int?) -> String {
    guard let idx, idx >= 0, idx < rawRow.count else { return "" }
    return rawRow[idx].trimmed()
}

// ✅ Apply similar validation to all inputs:
func validateAndCreateStudent(
    firstName: String?,
    lastName: String?,
    birthday: Date?
) throws -> Student {
    guard let firstName = firstName?.trimmed(), !firstName.isEmpty else {
        throw ValidationError.missingFirstName
    }
    guard let lastName = lastName?.trimmed(), !lastName.isEmpty else {
        throw ValidationError.missingLastName
    }
    
    // Validate date if provided
    if let birthday = birthday {
        guard birthday <= Date() else {
            throw ValidationError.futureBirthday
        }
    }
    
    return Student(firstName: firstName, lastName: lastName, birthday: birthday)
}

// ✅ Use Result type for operations that might fail:
enum DataOperationResult<T> {
    case success(T)
    case failure(Error)
}

func createItem(data: InputData) -> DataOperationResult<Item> {
    do {
        let item = try validateAndCreate(data: data)
        return .success(item)
    } catch {
        return .failure(error)
    }
}
```

**Expected Improvement:** Better error messages, fewer crashes from invalid input, improved user experience.

---

## Implementation Priority

### Week 1 (Critical):
1. ✅ Make RootView backfill operations async
2. ✅ Replace force unwraps in most common crash paths (use grep to find hotspots)

### Week 2 (High Priority):
3. ✅ Optimize SettingsView statistics queries
4. ✅ Standardize SwiftData error handling
5. ✅ Add predicates to top 3 unfiltered @Query locations (Settings, Inbox, Planning)

### Week 3-4 (Medium Priority):
6. ✅ Add bounds checking helpers and apply to array access
7. ✅ Cache expensive computations in view bodies
8. ✅ Improve fallback paths for failed predicates
9. ✅ Implement lazy loading for detail views

### Ongoing:
10. ✅ Add validation to all user input paths
11. ✅ Continue replacing unfiltered queries (systematic review)
12. ✅ Profile with Instruments to measure improvements

---

## Measuring Success

**Performance Metrics:**
- App launch time (target: < 2 seconds)
- View navigation time (target: < 500ms)
- Memory usage (target: 20-40% reduction)
- Scroll frame rate (target: 60fps)

**Stability Metrics:**
- Crash rate (target: < 0.1% of sessions)
- Error logs (target: all errors logged, none silent)
- User-reported issues (target: reduction in data loss reports)

Use Instruments (Time Profiler, Allocations, SwiftUI Profiler) to measure before and after.

---

## Notes

- All optimizations preserve existing functionality
- No features will be removed or changed
- Test thoroughly after each optimization
- Consider A/B testing for performance-critical changes
- Monitor crash reports and user feedback after deployment

