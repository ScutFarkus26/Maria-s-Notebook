// RestockView+Actions.swift
// The page's changes, all through RestockService. Taps on tiles and −/+
// save once per burst (800 ms after the last); a check-off, a sheet or a
// delete saves at once.

import SwiftUI
import CoreData

extension RestockView {

    // MARK: - Saving

    /// Saves after a burst of taps settles, so marking three staples is one
    /// save and one CloudKit push.
    func scheduleSave(reason: String) {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            saveCoordinator.save(viewContext, reason: reason)
        }
    }

    func flushPendingSave() {
        guard let pending = pendingSave else { return }
        pending.cancel()
        pendingSave = nil
        saveCoordinator.save(viewContext, reason: "Restock")
    }

    func saveNow(reason: String) {
        pendingSave?.cancel()
        pendingSave = nil
        saveCoordinator.save(viewContext, reason: reason)
    }

    /// Keeps one open need per staple when two devices opened one each.
    func reconcile() {
        guard RestockService.reconcile(in: viewContext) > 0 else { return }
        saveNow(reason: "Restock")
    }

    // MARK: - Staples

    func setLevel(_ staple: CDSupply, to level: RestockLevel) {
        guard RestockService.setLevel(staple, to: level, by: author, in: viewContext) else { return }
        scheduleSave(reason: "Mark \(staple.name) \(level.displayName)")
    }

    func addCommonStaple(_ name: String) {
        let details = RestockService.StapleDetails(name: name)
        guard let added = RestockService.addStaple(details, by: author, in: viewContext), added.isNew else { return }
        saveNow(reason: "Add a staple")
        let staple = added.object
        ToastService.shared.show("\(name) is on the shelf", type: .success, undoAction: {
            guard !staple.isDeleted, staple.managedObjectContext != nil else { return }
            RestockService.deleteStaple(staple, in: viewContext)
            saveNow(reason: "Remove a staple")
        })
    }

    func saveNote() {
        guard let staple = noteStaple else { return }
        noteStaple = nil
        guard RestockService.setNote(staple, to: noteText) else { return }
        saveNow(reason: "Staple note")
    }

    func deleteStaple() {
        guard let staple = deletingStaple else { return }
        deletingStaple = nil
        RestockService.deleteStaple(staple, in: viewContext)
        saveNow(reason: "Delete a staple")
    }

    // MARK: - Needs

    /// Checks a need off, with Undo: it's received, and its staple is Stocked.
    func checkOff(_ need: CDOrderItem) {
        guard let done = RestockService.checkOff(need, by: author, in: viewContext) else { return }
        saveNow(reason: "Check off")
        let verb = need.source == .office ? "Got" : "Received"
        ToastService.shared.show("\(verb) \(need.displayTitle)", type: .success, undoAction: {
            RestockService.undoCheckOff(done, in: viewContext)
            saveNow(reason: "Undo check off")
        })
    }

    func setQuantity(_ need: CDOrderItem, _ quantity: Int) {
        RestockService.setQuantity(need, to: quantity)
        scheduleSave(reason: "Quantity")
    }

    func markAskedFor(_ needs: [CDOrderItem]) {
        RestockService.markRequested(needs, from: OrderRequestRecipient.stored().label)
        saveNow(reason: "Mark asked for")
    }

    func markConfirmed(_ needs: [CDOrderItem]) {
        RestockService.markConfirmed(needs)
        saveNow(reason: "Mark confirmed")
    }

    func clearConfirmation(_ needs: [CDOrderItem]) {
        RestockService.clearConfirmation(needs)
        saveNow(reason: "Clear confirmation")
    }

    func moveBackToRequest(_ needs: [CDOrderItem]) {
        RestockService.moveBackToRequest(needs)
        saveNow(reason: "Move back to To Order")
    }

    func removeNeeds(_ needs: [CDOrderItem]) {
        RestockService.removeNeeds(needs, by: author, in: viewContext)
        saveNow(reason: "Remove from Restock")
    }

    func clearReceived() {
        removeNeeds(received)
        showingReceived = false
    }
}
