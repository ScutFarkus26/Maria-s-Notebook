# Todos

The Todos screen was taken out on 2026-11-22 (`Cut: The To-dos screen`, plan `../Plans/Plan - Cut unused features and close the lesson loop.md`). The to-do records stay, and so does everything else that uses them:

- **Today's to-do section** (`Today/Views/Sections/TodayViewTodoSection.swift`) lists what `TodoListFilter.isOnToday` / `isDueOrPlanned` pick. `TodoListFilter` is now a caseless enum with just those rules and `isDue`.
- **Meetings' For Me to Do**, a child's Watching section, and work rows show their own to-dos.
- **New and edit forms** (`NewTodoForm`, `EditTodoForm`) stay. `EditTodoForm` has **Delete To-do** with a confirmation, since the screen was the only other place to delete one; it is the only delete in the app now.
- **Tide sharing** (`TIDE_SHARING.md`) and the Claude to-do tools (`list_todos`, `update_todo`) are unchanged.
- Someday to-dos and ones tied to work don't go to Tide, so with the screen gone they are reached on their work rows or through chat (`list_todos`).
- The `todoTagOrder` and `todoHideCompleted` preference keys stay on the backed-up preferences list, so a settings backup doesn't change, though nothing reads them now.

Rules that still hold, from the 2026-11-03 bug hunt (`../Reviews/Bug hunt 2026-11-03.md`, #49-#58):

- **Checklists inside a to-do** can be ticked, renamed, deleted and added in the editor, and a repeat copies them unticked.
- **Someday** keeps its deadline. A to-do whose deadline is today or earlier joins Today as overdue.
- **Weekends:** Today shows to-dos by the real day, so a Saturday to-do shows on Saturday and Sunday's aren't overdue.

The screen's own rules (Clear Completed, Batch Delete, the sidebar lists) went with it; read them in `git show retired/2026-11-cuts:"docs/Technical notes/TODOS.md"`.
