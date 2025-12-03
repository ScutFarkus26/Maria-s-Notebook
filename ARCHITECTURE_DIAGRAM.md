# WorkView Architecture

## Component Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                          WorkView                            │
│  - Manages @Query for data sources                          │
│  - Coordinates UI state                                      │
│  - Syncs filters with @SceneStorage                         │
│  - Platform detection (compact vs regular)                  │
└────────────────┬────────────────────────────────────────────┘
                 │
       ┌─────────┴─────────┐
       │                   │
       ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ compactLayout│    │regularLayout │
│  (iOS)       │    │(macOS/iPad)  │
└──────┬───────┘    └───────┬──────┘
       │                    │
       └────────┬───────────┘
                │
    ┌───────────┼───────────┬──────────────┐
    │           │           │              │
    ▼           ▼           ▼              ▼
┌─────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐
│ Empty   │ │ Student │ │  Work    │ │  Work    │
│ State   │ │ Filter  │ │ View     │ │ Content  │
│ View    │ │ View    │ │ Sidebar  │ │  View    │
└─────────┘ └─────────┘ └──────────┘ └────┬─────┘
                                            │
                                            ▼
                                   ┌────────────────┐
                                   │ Grouped        │
                                   │ Works View     │
                                   └────────────────┘
```

## Data Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    SwiftData Queries                          │
│  @Query students, lessons, studentLessons, workItems         │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │     WorkLookupService         │
        │  - Creates lookup dictionaries│
        │  - Provides helper methods    │
        │  - Calculates derived values  │
        └───────────────┬───────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │        WorkFilters             │
        │  - Manages filter state       │
        │  - Applies filter logic       │
        │  - Synced with @SceneStorage  │
        └───────────────┬───────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │    Filtered Work Items        │
        └───────────────┬───────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
            ▼                       ▼
    ┌──────────────┐      ┌────────────────┐
    │ Display      │      │ Grouping       │
    │ Directly     │      │ Service        │
    │ (no grouping)│      │ - Groups items │
    └──────────────┘      └────────────────┘
```

## State Management

```
┌─────────────────────────────────────────────┐
│            @SceneStorage                    │
│  - selectedSubjectStorage                   │
│  - selectedStudentIDsStorage                │
│  - searchTextStorage                        │
│  - groupingStorage                          │
└──────────────────┬──────────────────────────┘
                   │
         ┌─────────┴─────────┐
         │                   │
         ▼                   ▼
    syncFilters         syncFilters
    FromStorage         ToStorage
         │                   ▲
         └────────┬──────────┘
                  │
                  ▼
         ┌────────────────┐
         │  WorkFilters   │
         │  @Observable   │
         │  - Published   │
         │    changes     │
         └────────────────┘
```

## Service Layer

```
┌────────────────────────────────────────────────────────┐
│                  Service Objects                        │
│  (Pure Swift, no SwiftUI dependencies)                 │
└─────────────────────────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐
│ WorkFilters      │  │ WorkLookupService│  │ WorkGrouping │
│                  │  │                  │  │ Service      │
│ - Filter state   │  │ - Dictionaries   │  │              │
│ - Filter logic   │  │ - Subjects list  │  │ - Section    │
│ - Grouping mode  │  │ - Date calc      │  │   order      │
│                  │  │ - Name format    │  │ - Section    │
│ @Observable      │  │                  │  │   icons      │
│                  │  │ struct           │  │ - Grouping   │
│                  │  │                  │  │   algorithms │
└──────────────────┘  └──────────────────┘  └──────────────┘
```

## View Components

```
┌────────────────────────────────────────────────────────┐
│                   View Layer                            │
│  (SwiftUI views, platform-specific UI)                 │
└─────────────────────────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐
│ WorkView         │  │ WorkViewSidebar  │  │ Student      │
│                  │  │                  │  │ FilterView   │
│ - Coordinator    │  │ - Filter UI      │  │              │
│ - Data queries   │  │ - Group By       │  │ - Search     │
│ - Scene storage  │  │ - Subject list   │  │ - Multi-     │
│ - Layouts        │  │                  │  │   select     │
└──────────────────┘  └──────────────────┘  └──────────────┘

┌──────────────────┐  ┌──────────────────┐
│ WorkContentView  │  │ WorkEmptyState   │
│                  │  │ View             │
│ - Ungrouped      │  │                  │
│ - Grouped        │  │ - No work        │
│ - Grid display   │  │ - No matches     │
└──────────────────┘  └──────────────────┘

┌──────────────────┐
│ GroupedWorksView │
│                  │
│ - Section        │
│   headers        │
│ - Section        │
│   content        │
└──────────────────┘
```

## Benefits of This Architecture

### 1. **Testability**
```
✅ WorkFilters → Unit testable
✅ WorkLookupService → Unit testable
✅ WorkGroupingService → Unit testable
❌ Views → UI/Snapshot tests only
```

### 2. **Reusability**
```
StudentFilterView → Can be used in other views
WorkFilters → Can filter any work list
WorkLookupService → Generic lookup utilities
```

### 3. **Maintainability**
```
Before: 650-line monolithic file
After: 8 focused files (60-280 lines each)
```

### 4. **Extensibility**
```
Add new filter?
  → Extend WorkFilters

Add new grouping?
  → Add case to WorkFilters.Grouping
  → Extend WorkGroupingService

Change UI?
  → Modify view files only
  → Logic remains unchanged
```

## Platform Differences

```
┌──────────────────────────────────────────────────────┐
│                   iOS (Compact)                       │
│                                                       │
│  ┌────────────────────────────────────────────────┐ │
│  │ Navigation Bar                                 │ │
│  │  [Filter Menu] [Add Button]                    │ │
│  ├────────────────────────────────────────────────┤ │
│  │ Search Field                                   │ │
│  ├────────────────────────────────────────────────┤ │
│  │                                                │ │
│  │          Work Content                          │ │
│  │                                                │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│              macOS/iPad (Regular)                     │
│                                                       │
│  ┌─────────┬────────────────────────────────────┐   │
│  │ Sidebar │ Main Content                       │   │
│  │         │                                    │   │
│  │ Student │                                    │   │
│  │ Filter  │        Work Content                │   │
│  │         │                              [+]   │   │
│  │ Search  │                                    │   │
│  │         │                                    │   │
│  │ Group   │                                    │   │
│  │ By      │                                    │   │
│  │         │                                    │   │
│  │ Subjects│                                    │   │
│  └─────────┴────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

## Dependency Graph

```
WorkView
  ├─ depends on → WorkFilters (state)
  ├─ depends on → WorkLookupService (data)
  ├─ depends on → StudentFilterView (UI)
  ├─ depends on → WorkViewSidebar (UI)
  ├─ depends on → WorkEmptyStateView (UI)
  └─ depends on → WorkContentView (UI)

WorkContentView
  ├─ depends on → WorkFilters (grouping)
  ├─ depends on → WorkLookupService (data)
  └─ depends on → GroupedWorksView (UI)

GroupedWorksView
  ├─ depends on → WorkFilters.Grouping
  ├─ depends on → WorkGroupingService
  └─ depends on → WorkCardsGridView (existing)

WorkViewSidebar
  ├─ depends on → WorkFilters (binding)
  ├─ depends on → StudentFilterView (UI)
  └─ depends on → SidebarFilterButton (existing)

StudentFilterView
  └─ depends on → WorkFilters (binding for IDs)

WorkFilters
  └─ no dependencies (pure logic)

WorkLookupService
  └─ no dependencies (pure logic)

WorkGroupingService
  └─ no dependencies (pure logic)

WorkEmptyStateView
  └─ no dependencies (simple view)
```
