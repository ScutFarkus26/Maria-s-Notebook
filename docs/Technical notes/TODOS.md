# Todos

Rules for the Todos screen, from the 2026-11-03 bug hunt (`../Reviews/Bug hunt 2026-11-03.md`, #49-#58).

- **Clear Completed** deletes only the completed to-dos in the list on screen (`TodoListScope.completedToClear`), whether or not Hide Completed is on. It asks first with the count, and is greyed out where no completed to-dos show (Inbox, Today and Upcoming never list them). It once deleted every completed to-do in the notebook.
- **Batch Delete** asks with a count too. The Select-mode selection (`TodoBatchSelection`) is cleared whenever the list changes: a sidebar pick, a filter, a Tide list or the search text.
- **Checklists inside a to-do** can be ticked, renamed, deleted and added in the editor, and a repeat copies them unticked.
- **Someday** keeps its deadline. A to-do whose deadline is today or earlier joins Today as overdue.
- **Weekends:** Today shows to-dos by the real day, so a Saturday to-do shows on Saturday and Sunday's aren't overdue. The + button starts a new to-do on the later of the shown day and the real day.
