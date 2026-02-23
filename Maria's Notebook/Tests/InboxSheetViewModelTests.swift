#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Selection Tests

@Suite("InboxSheetViewModel Selection Tests", .serialized)
@MainActor
struct InboxSheetViewModelSelectionTests {

    @Test("Initial state has empty selection")
    func initialStateHasEmptySelection() {
        let vm = InboxSheetViewModel()

        #expect(vm.selected.isEmpty)
        #expect(vm.isSelectionMode == false)
    }

    @Test("toggleSelection adds unselected ID")
    func toggleSelectionAddsUnselectedID() {
        let vm = InboxSheetViewModel()
        let id = UUID()

        vm.toggleSelection(id)

        #expect(vm.selected.contains(id))
        #expect(vm.isSelectionMode == true)
    }

    @Test("toggleSelection removes selected ID")
    func toggleSelectionRemovesSelectedID() {
        let vm = InboxSheetViewModel()
        let id = UUID()

        vm.toggleSelection(id)
        vm.toggleSelection(id)

        #expect(!vm.selected.contains(id))
        #expect(vm.isSelectionMode == false)
    }

    @Test("Multiple IDs can be selected")
    func multipleIDsCanBeSelected() {
        let vm = InboxSheetViewModel()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.toggleSelection(id1)
        vm.toggleSelection(id2)
        vm.toggleSelection(id3)

        #expect(vm.selected.count == 3)
        #expect(vm.selected.contains(id1))
        #expect(vm.selected.contains(id2))
        #expect(vm.selected.contains(id3))
    }

    @Test("clearSelection removes all selected IDs")
    func clearSelectionRemovesAllSelectedIDs() {
        let vm = InboxSheetViewModel()
        let id1 = UUID()
        let id2 = UUID()

        vm.toggleSelection(id1)
        vm.toggleSelection(id2)
        vm.clearSelection()

        #expect(vm.selected.isEmpty)
        #expect(vm.isSelectionMode == false)
    }

    @Test("isSelectionMode returns true when selection is not empty")
    func isSelectionModeReturnsTrueWhenNotEmpty() {
        let vm = InboxSheetViewModel()

        #expect(vm.isSelectionMode == false)

        vm.toggleSelection(UUID())

        #expect(vm.isSelectionMode == true)
    }
}

// MARK: - Consolidation Eligibility Tests

@Suite("InboxSheetViewModel Consolidation Tests", .serialized)
@MainActor
struct InboxSheetViewModelConsolidationTests {

    private func makeLessonAssignment(lessonID: UUID) -> LessonAssignment {
        LessonAssignment(lessonID: lessonID)
    }

    @Test("canConsolidate returns false when selection is empty")
    func canConsolidateReturnsFalseWhenEmpty() {
        let vm = InboxSheetViewModel()

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [])

        #expect(canConsolidate == false)
    }

    @Test("canConsolidate returns false when only one item selected")
    func canConsolidateReturnsFalseWithSingleItem() throws {
        let vm = InboxSheetViewModel()
        let lessonID = UUID()
        let la = makeLessonAssignment(lessonID: lessonID)

        vm.toggleSelection(la.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la])

        #expect(canConsolidate == false)
    }

    @Test("canConsolidate returns false when selected items have different lesson IDs")
    func canConsolidateReturnsFalseWithDifferentLessons() throws {
        let vm = InboxSheetViewModel()
        let la1 = makeLessonAssignment(lessonID: UUID())
        let la2 = makeLessonAssignment(lessonID: UUID())

        vm.toggleSelection(la1.id)
        vm.toggleSelection(la2.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la1, la2])

        #expect(canConsolidate == false)
    }

    @Test("canConsolidate returns true when two items with same lesson ID are selected")
    func canConsolidateReturnsTrueWithSameLessonID() throws {
        let vm = InboxSheetViewModel()
        let lessonID = UUID()
        let la1 = makeLessonAssignment(lessonID: lessonID)
        let la2 = makeLessonAssignment(lessonID: lessonID)

        vm.toggleSelection(la1.id)
        vm.toggleSelection(la2.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la1, la2])

        #expect(canConsolidate == true)
    }

    @Test("canConsolidate returns true when multiple groups can be consolidated")
    func canConsolidateReturnsTrueWithMultipleGroups() throws {
        let vm = InboxSheetViewModel()
        let lessonID1 = UUID()
        let lessonID2 = UUID()

        let la1 = makeLessonAssignment(lessonID: lessonID1)
        let la2 = makeLessonAssignment(lessonID: lessonID1)
        let la3 = makeLessonAssignment(lessonID: lessonID2)
        let la4 = makeLessonAssignment(lessonID: lessonID2)

        vm.toggleSelection(la1.id)
        vm.toggleSelection(la2.id)
        vm.toggleSelection(la3.id)
        vm.toggleSelection(la4.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la1, la2, la3, la4])

        #expect(canConsolidate == true)
    }

    @Test("canConsolidate returns true even if one group has only one item")
    func canConsolidateReturnsTrueWithMixedGroups() throws {
        let vm = InboxSheetViewModel()
        let lessonID1 = UUID()
        let lessonID2 = UUID()

        // Group 1: two items (can consolidate)
        let la1 = makeLessonAssignment(lessonID: lessonID1)
        let la2 = makeLessonAssignment(lessonID: lessonID1)
        // Group 2: one item (cannot consolidate alone)
        let la3 = makeLessonAssignment(lessonID: lessonID2)

        vm.toggleSelection(la1.id)
        vm.toggleSelection(la2.id)
        vm.toggleSelection(la3.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la1, la2, la3])

        // Should return true because group 1 has 2+ items
        #expect(canConsolidate == true)
    }

    @Test("canConsolidate only considers selected items")
    func canConsolidateOnlyConsidersSelectedItems() throws {
        let vm = InboxSheetViewModel()
        let lessonID = UUID()

        let la1 = makeLessonAssignment(lessonID: lessonID)
        let la2 = makeLessonAssignment(lessonID: lessonID)
        let la3 = makeLessonAssignment(lessonID: lessonID)

        // Only select one item
        vm.toggleSelection(la1.id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [la1, la2, la3])

        // Should return false because only one item is selected
        #expect(canConsolidate == false)
    }
}

// MARK: - Toast Tests

@Suite("InboxSheetViewModel Toast Tests", .serialized)
@MainActor
struct InboxSheetViewModelToastTests {

    @Test("toastMessage is initially nil")
    func toastMessageIsInitiallyNil() {
        let vm = InboxSheetViewModel()

        #expect(vm.toastMessage == nil)
    }
}

// MARK: - Callback Tests

@Suite("InboxSheetViewModel Callback Tests", .serialized)
@MainActor
struct InboxSheetViewModelCallbackTests {

    @Test("onUpdateOrder callback can be set")
    func onUpdateOrderCallbackCanBeSet() {
        let vm = InboxSheetViewModel()
        var callbackCalled = false

        vm.onUpdateOrder = { _ in
            callbackCalled = true
        }

        vm.onUpdateOrder?("test")

        #expect(callbackCalled == true)
    }

    @Test("onUpdateOrder receives correct value")
    func onUpdateOrderReceivesCorrectValue() {
        let vm = InboxSheetViewModel()
        var receivedValue: String?

        vm.onUpdateOrder = { value in
            receivedValue = value
        }

        vm.onUpdateOrder?("test-order")

        #expect(receivedValue == "test-order")
    }
}

// MARK: - Edge Case Tests

@Suite("InboxSheetViewModel Edge Case Tests", .serialized)
@MainActor
struct InboxSheetViewModelEdgeCaseTests {

    @Test("Toggle same ID multiple times works correctly")
    func toggleSameIDMultipleTimesWorksCorrectly() {
        let vm = InboxSheetViewModel()
        let id = UUID()

        vm.toggleSelection(id)
        #expect(vm.selected.contains(id))

        vm.toggleSelection(id)
        #expect(!vm.selected.contains(id))

        vm.toggleSelection(id)
        #expect(vm.selected.contains(id))

        vm.toggleSelection(id)
        #expect(!vm.selected.contains(id))
    }

    @Test("Clear selection when already empty does not crash")
    func clearSelectionWhenAlreadyEmptyDoesNotCrash() {
        let vm = InboxSheetViewModel()

        vm.clearSelection()

        #expect(vm.selected.isEmpty)
    }

    @Test("canConsolidate handles empty list gracefully")
    func canConsolidateHandlesEmptyListGracefully() {
        let vm = InboxSheetViewModel()
        let id = UUID()

        vm.toggleSelection(id)

        let canConsolidate = vm.canConsolidate(orderedUnscheduledLessons: [])

        #expect(canConsolidate == false)
    }

    @Test("Selection state is maintained across multiple operations")
    func selectionStateIsMaintainedAcrossMultipleOperations() {
        let vm = InboxSheetViewModel()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.toggleSelection(id1)
        vm.toggleSelection(id2)
        vm.toggleSelection(id3)

        #expect(vm.selected.count == 3)

        vm.toggleSelection(id2)

        #expect(vm.selected.count == 2)
        #expect(vm.selected.contains(id1))
        #expect(!vm.selected.contains(id2))
        #expect(vm.selected.contains(id3))
    }
}

#endif
