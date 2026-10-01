// StudentsView+SaveGate.swift
// Which saves can move a roster signal.
//
// Split from the view, which is past SwiftLint's type-length limit, the same
// way `WorksAgendaView+DataHelpers.swift` holds the agenda's gate.

import CoreData

extension StudentsView {
    /// True when a `NSManagedObjectContextDidSave` touched a table a roster
    /// signal is read from (`StudentsViewModel.signalInputEntities`). Fails
    /// open on an unrecognised payload — see `ManagedObjectChangeScope.saveTouches`.
    nonisolated static func saveTouchesSignals(_ userInfo: [AnyHashable: Any]?) -> Bool {
        ManagedObjectChangeScope.saveTouches(StudentsViewModel.signalInputEntities, in: userInfo)
    }
}
