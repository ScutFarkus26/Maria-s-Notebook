# Widgets & Control Center — handoff (Siri top‑10, item #7)

Everything else in the Siri top‑10 shipped in the app target. **Widgets and
Control Center controls cannot** — they must live in a **Widget Extension
target**, and a new target can only be created in Xcode (it also needs an
**App Group** capability added to two targets' entitlements). This doc is the
exact recipe. None of the code below has been compiled (there's no extension
target yet), so treat it as a verified‑pattern starting point and build once in
Xcode.

## Why a separate target

`Widget`, `WidgetBundle`, and `ControlWidget` only run inside a Widget Extension
process. They can't go in the app target (the app already owns `@main`, and the
system loads widgets/controls from the extension). The app and extension share
data through an **App Group** container.

## One‑time Xcode setup (≈10 min)

1. **File ▸ New ▸ Target… ▸ Widget Extension.** Name it `MariasNotebookWidgets`.
   Uncheck "Include Live Activity" / "Include Configuration App Intent" for now.
   Set its **iOS Deployment Target to 27.0** to match the app.
2. **App Group on both targets.** Select the app target ▸ Signing & Capabilities
   ▸ + Capability ▸ **App Groups** ▸ add `group.DanielSDeBerry.MariasNoteBook`.
   Repeat on the `MariasNotebookWidgets` target, selecting the same group.
   (The existing `TodoWidgetProvider.swift` comment mentions
   `sequence.com.marianotebook.shared`; prefer a `group.<bundleID>` identifier so
   it matches the app's CloudKit/bundle naming — just keep both targets identical.)
3. **Share the existing widget UI.** The repo already has
   `Maria's Notebook/Services/TodoWidgetProvider.swift` with finished Small/Medium/
   Large layouts. In the File Inspector, add it to the `MariasNotebookWidgets`
   target membership (or move it into the extension folder).
4. **Share any types the widget needs** the same way (e.g. `AppColors`). Keep this
   list small — widgets should read a tiny precomputed snapshot, not the whole app.
5. Build the extension scheme once and resolve any missing‑type errors by adding
   those files to the extension target.

## Control Center / Lock Screen / Action button control

Drop this in the extension target. It adds a one‑tap control that opens the app
(the simplest reliable control — a control button runs a *parameterless* intent,
so it can't gather "which student / what text" by itself).

```swift
import AppIntents
import SwiftUI
import WidgetKit

// Self-contained launch intent for the control (lives in the extension target).
struct LaunchMariasNotebookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Maria's Notebook"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}

struct OpenNotebookControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DanielSDeBerry.MariasNoteBook.control.open") {
            ControlWidgetButton(action: LaunchMariasNotebookIntent()) {
                Label("Maria's Notebook", systemImage: "square.and.pencil")
            }
        }
        .displayName("Open Maria's Notebook")
        .description("Open the notebook to log an observation.")
    }
}
```

**To make the control jump straight to observation capture** (nicer than a bare
launch): add a parameterless `StartObservationIntent` in the **app** target's
`Siri/` folder with `openAppWhenRun = true` that sets a new
`AppRouter` trigger (e.g. `triggerQuickNote = true`), then have `RootView`
present the Quick Note sheet when that flag flips — mirror the existing
`triggerRecordPractice` / `triggerNewWorkItem` pattern in
`AppCore/RootView.swift`. Share that intent file with the extension target and
use it as the control's `action:` instead of `LaunchMariasNotebookIntent`.

## Widget bundle (entry point)

```swift
import WidgetKit
import SwiftUI

@main
struct MariasNotebookWidgets: WidgetBundle {
    var body: some Widget {
        TodoWidget()            // wraps the provider/views in TodoWidgetProvider.swift
        OpenNotebookControl()   // the Control Center control above
    }
}
```

`TodoWidgetProvider.swift` already defines the timeline entry, provider, and the
three size layouts. Its `getTimeline(...)` is a stub — wire it to real data via
the App Group:

- **Simplest:** when the app saves todos, write a tiny `Codable` snapshot
  (title, isCompleted, dueDate, isOverdue) to
  `UserDefaults(suiteName: "group.DanielSDeBerry.MariasNoteBook")` or a JSON file
  in `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
  The widget reads that snapshot in `getTimeline`. This avoids giving the widget
  the full Core Data + CloudKit stack.
- **Heavier:** point the widget at the same Core Data store by putting the
  `.sqlite` files in the App Group container. More moving parts; only do this if
  the snapshot approach proves too limiting.

After the timeline is wired, call `WidgetCenter.shared.reloadAllTimelines()`
from the app whenever todos change.

## Acceptance check

- Widget gallery shows "Maria's Notebook" widgets; Add a Control (Control Center
  edit / Lock Screen) shows the Open control.
- Tapping the control opens the app.
- The Todo widget shows real counts after a todo change + reload.
