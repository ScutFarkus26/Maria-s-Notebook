# Feature Ownership Conventions

These conventions define where new code belongs and how existing code should move during the repository reorganization. They describe source ownership, not new Swift modules; Maria's Notebook remains a single app target unless a separate modularization decision is made later.

## Core rule

Place a declaration with the feature that owns its behavior. Keep it shared only when multiple unrelated features genuinely depend on it.

Use this test:

1. If one feature consumes the declaration, it belongs to that feature.
2. If several related screens consume it, it belongs to their common feature or subdomain.
3. If several unrelated features consume it, it may belong in a shared layer.
4. If it exists for app startup, persistence, networking, synchronization, operating-system integration, or dependency wiring, it belongs in app infrastructure.

## Folder responsibilities

### `AppCore`

`AppCore` is reserved for application composition:

- app lifecycle and launch
- dependency construction and environment injection
- root navigation, routing, and window registration
- global commands and app-wide shell UI
- persistence bootstrap and global configuration

Feature screens, feature view models, and feature-specific helpers do not belong in `AppCore`.

### Feature folders

A top-level feature folder owns its complete vertical slice where practical:

- views and presentation state
- feature view models and coordinators
- feature-specific services, loaders, caches, and helpers
- feature-specific domain types
- subdomains that are meaningful to people working on the feature

Prefer domain-oriented subfolders such as `Students/Progress` or `Work/Practice` over a large generic `Views` folder when a feature becomes broad.

### `Components`

`Components` contains reusable UI primitives consumed by at least two unrelated features. Examples include shared pills, search controls, avatars, and layout helpers.

A component used by only one feature moves to that feature. Similar-looking views should not be generalized until they share stable behavior and semantics.

### `Services`

`Services` contains cross-feature infrastructure and system integrations, including synchronization, notifications, external APIs, and application-wide coordination.

A service that implements one feature's rules moves to that feature, even if its type name ends in `Service`. Stateful presentation objects belong with their feature rather than in `Services`.

### `Models`

`Models` contains persistence types and domain types that cross feature boundaries. A lightweight type used only inside one feature belongs with that feature unless Core Data generation or shared-store routing requires central ownership.

### `Repositories`

`Repositories` remains the centralized data-access boundary. Repositories should not move merely to make feature folders visually symmetrical. A future change to this boundary requires an architecture decision because it affects dependency injection and persistence conventions.

### Tests

Tests mirror production ownership. Shared fixtures and test infrastructure belong in a test `Support` folder. Moving tests must not rename test types or methods in the same commit.

## Dependency direction

- `AppCore` composes features and shared infrastructure.
- Features may depend on shared models, repositories, components, and infrastructure.
- Shared layers must not depend on feature UI.
- One feature should not reach into another feature's private presentation helpers; promote a stable shared abstraction or route through app composition instead.

Because the app is currently one Swift target, review and folder placement enforce these boundaries. Folder moves do not claim compiler-enforced modularity.

## Moving code safely

An organization-only commit should:

1. Move one coherent feature or subdomain.
2. Keep type names, access levels, and behavior unchanged unless compilation requires a narrowly documented fix.
3. Avoid formatting unrelated lines.
4. Update source comments and documentation paths.
5. Confirm synchronized-folder target membership has not changed unexpectedly.
6. Build macOS and iOS, run relevant tests, and record known baseline exceptions.

If ownership is ambiguous, leave the file in place and record the exception in the repository organization plan. A questionable move is more expensive than a temporary imperfect folder.

## Examples for this repository

- Today views, `TodayViewModel`, loaders, caches, and navigation helpers belong under `Today`.
- Todo screens, forms, models, and Todo-specific services belong under `Todos`.
- Observation editing and quick capture belong under `Notes`, while stable UI primitives used elsewhere remain in `Components`.
- Lesson-planning rules belong under `Planning`; a lesson-planning view model does not belong in the global `Services` folder.
- CloudKit, backup transport, notifications, and external AI clients remain infrastructure unless a later architecture decision changes their boundary.
