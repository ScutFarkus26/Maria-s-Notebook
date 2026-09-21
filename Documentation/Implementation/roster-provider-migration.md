# Roster and lesson-catalog migration (items #28/#29)

**What the stores are.** `RosterStore` (`Students/Roster/`) and `LessonCatalog` (`Lessons/`) are
`@Observable @MainActor` classes, each wrapping one `NSFetchedResultsController` on the view context
(`Utils/FetchedTable.swift`). The controller listens to the same `NSManagedObjectContextObjectsDidChange`
an `@FetchRequest` did — local edits, saves, CloudKit imports merged by `automaticallyMergesChangesFromParent`
— and its delegate rebuilds the cached arrays once per change; views reading a store property are
invalidated through observation. Rows are the managed objects, so `@ObservedObject` rows keep working.
Both hang off `AppDependencies` as lazy services (`dependencies.roster`, `dependencies.lessonCatalog`),
so the Sample Class switch — a fresh `AppDependencies` on its own stack — gets its own pair.

Surface: `roster.all` (every student once, first → last name → manual order; CloudKit duplicate-ID rows
dropped first-wins, so `uniqueByID` is already applied), `.enrolled`, `.byID`, `.student(id:)`.
`lessonCatalog.all` (area → sequence → orderInSequence → name; not de-duplicated), `.byID` (first wins),
`.lesson(id:)`, `.lessons(area:sequence:)` (trimmed, case-insensitive, `orderInSequence` order),
`.sortedByAreaAndSortIndex` (the lesson-picking sheets' list order). Neither applies the test-student
preference: keep the view's `@TestStudentVisibility` and filter exactly as before.

Every migrated view adds `@Environment(\.dependencies) private var dependencies` **to the struct that
held the fetch** (trap 1) and deletes the `@FetchRequest` + `FetchedResults` declaration.

**(a) `studentsRaw` + `filterEnrolled()` / `testStudents.visible(_:)`:** the enrolled-predicate fetch
`testStudents.visible(studentsRaw)` becomes `testStudents.visible(dependencies.roster.enrolled)`.
A `sortDescriptors: []` fetch filtered with `TestStudentsFilter.filterVisible(Array(raw).uniqueByID, …)`
keeps withdrawn students, so it maps to `TestStudentsFilter.filterVisible(dependencies.roster.all, …)` (trap 2).

**(b) `allStudents` used only for lookup:** `allStudents.first { $0.id == id }` → `dependencies.roster.student(id: id)`.

**(c) `lessons` used only for lookup by ID / a `[UUID: CDLesson]` map:**
`lessons.first(where: { $0.id == id })` → `dependencies.lessonCatalog.lesson(id: id)`;
`Dictionary(lessons.compactMap …, uniquingKeysWith: { first, _ in first })` → `dependencies.lessonCatalog.byID`;
`lessons.filter { same area & sequence }.sorted { orderInSequence }` → `lessonCatalog.lessons(area:sequence:)`.
When a view reads `lessons` many times, keep a one-line alias: `private var lessons: [CDLesson] { dependencies.lessonCatalog.all }`.

**(d) A `FetchedResults` passed down as a parameter** (`lessons: Array(lessons)`): the child already takes
an array, so pass `dependencies.lessonCatalog.all` / the filtered roster; the child does not change. A sheet
that *lists* the catalog in its fetch order (`AddLessonToInboxSheet`: area, sortIndex) reads
`sortedByAreaAndSortIndex`; one that re-sorts itself (`LessonSearchPicker`) reads `all`.

**Trap 1 — the environment is in the wrong struct.** `grep -c 'Environment(\.dependencies)'` said
`PresentationDetailView.swift` had one; it belonged to `PresentationDetailContentView` further down. Check
the line number against the struct that owns the fetch, or the build fails on `dependencies`.

**Trap 2 — the two test-student filters are not interchangeable.** `testStudents.visible(_:)` runs
`visibleRoster`, which *also* drops withdrawn students; `TestStudentsFilter.filterVisible(_:show:namesRaw:)`
does not. Map the former to `roster.enrolled` and the latter to `roster.all`; swapping them silently changes
which children a presentation can be given to.

Out of scope for this pattern: a fetch with a non-roster predicate or a `$fetchRequest` binding.
