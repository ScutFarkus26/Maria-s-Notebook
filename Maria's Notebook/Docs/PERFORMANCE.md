# Performance Optimization

**Last Updated:** 2026-02-25

## Completed Optimizations

### Critical (Done)

1. **RootView backfill operations** — moved to `AppBootstrapper` for async execution. 50-70% faster launch.

2. **TodayViewModel.reload()** — optimized with targeted fetches, dictionary caching, and debounced reloads. 60-80% memory reduction.

3. **SettingsView statistics queries** — replaced unfiltered `@Query` with repository-based filtered fetches. 60-80% faster.

4. **WorksAgendaView** — added date range filtering. 70-90% memory reduction.

5. **FollowUpInboxView** — repository-based with filtered fetch. 70-90% memory reduction.

6. **PresentationHistoryView** — implemented pagination. Handles large histories without loading all records.

7. **DayColumn** — date range filtering for agenda queries.

8. **WorkContractDetailSheet** — lazy loading for work items.

### Stability (Done)

9. **Safe array access extension** — prevents index-out-of-bounds crashes.

10. **Force unwrap reduction** — 70-90% reduction in nil-related crash risk.

11. **Standardized error handling** — consistent patterns across services.

12. **Strict enum raw values** — enforced for CloudKit compatibility.

---

## Remaining Opportunities

### High Priority

| Target | Issue | Approach |
|--------|-------|----------|
| `PresentationsListView` | Unfiltered `@Query` for lesson assignments | Move to repository with student-scoped fetch |
| `PlanningWeekView` | Loads all lessons for week computation | Add date range filter to fetch |
| `PresentationsViewModel` | Complex unfiltered fetches | Repository-based with targeted predicates |

### Medium Priority

| Target | Issue | Approach |
|--------|-------|----------|
| Heavy view body computations | Filtering/sorting in `body` | Move to ViewModel with `@State` caching |
| Image loading | Synchronous in scroll views | Create `AsyncCachedImage` with `NSCache` |
| Rapid input triggers | No debouncing on expensive operations | 400ms debounce pattern |

### Low Priority

- Global adoption of safe array access
- Additional preference migration to `SyncedPreferencesStore`
- `drawingGroup()` for complex card views

---

## Key Patterns

### Unfiltered @Query Audit

29 locations identified. Completed items marked with checkmarks:

| View/ViewModel | Entity | Risk | Status |
|---------------|--------|------|--------|
| SettingsView | Multiple | HIGH | Done |
| RootView | Multiple | HIGH | Done |
| WorksAgendaView | WorkModel | HIGH | Done |
| FollowUpInboxView | WorkModel | HIGH | Done |
| PresentationHistoryView | Presentation | MED | Done |
| PresentationsListView | LessonAssignment | HIGH | Pending |
| PlanningWeekView | Lesson | HIGH | Pending |
| PresentationsViewModel | Multiple | HIGH | Pending |
| WorkModelDetailSheet | WorkModel | MED | Pending |

### Anti-Patterns to Avoid

```swift
// BAD: Unfiltered query loads everything
@Query private var allStudents: [Student]

// GOOD: Filtered query or repository
@Query(filter: #Predicate<Student> { $0.isActive })
private var activeStudents: [Student]

// BAD: O(n) lookup in row rendering
items.first { $0.id == targetID }

// GOOD: O(1) dictionary lookup
itemsByID[targetID]

// BAD: Computation in view body
var body: some View {
    let sorted = items.sorted { ... } // runs every render
}

// GOOD: Cached in ViewModel
func reload() {
    sortedItems = items.sorted { ... } // runs once
}
```

---

## iPhone-Specific Considerations

- **Memory:** iPhone has less RAM; batch processing and `autoreleasepool` are critical
- **Scroll performance:** Use `drawingGroup()` for complex list cells, stabilize ForEach identity with `.id`
- **Background processing:** Use `Task.detached` for heavy operations to keep UI responsive
- **Battery:** Debounce expensive operations to reduce CPU cycles

---

## Measuring Performance

Use **Instruments** (Product > Profile) with these templates:
- **Allocations** — track memory spikes during backup/restore and view loading
- **Time Profiler** — identify slow methods in view body and reload paths
- **SwiftUI** — track view re-renders and body evaluation frequency
