// InboxDropDelegate.swift
// The inbox's own drop target: it reorders unscheduled presentations by
// dropping one between two others. Split out of `InboxSheetView.swift`, which
// is at SwiftLint's file-length limit.

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct InboxDropDelegate: DropDelegate {
  let getCurrent: () -> [CDLessonAssignment]
  let itemFramesProvider: () -> [UUID: CGRect]
  let onTargetChange: (Bool) -> Void
  let onInsertionIndexChange: (Int?) -> Void
  let performDropHandler: ([NSItemProvider], CGPoint) -> Bool
  func dropEntered(info: DropInfo) {
    onTargetChange(true)
    onInsertionIndexChange(computeIndex(info))
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    onInsertionIndexChange(computeIndex(info))
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    onTargetChange(false)
    onInsertionIndexChange(nil)
  }

  func validateDrop(info: DropInfo) -> Bool {
    return info.hasItemsConforming(to: [UTType.text])
  }

  func performDrop(info: DropInfo) -> Bool {
    onTargetChange(false)
    onInsertionIndexChange(nil)
    let providers = info.itemProviders(for: [UTType.text])
    return performDropHandler(providers, info.location)
  }

  private func computeIndex(_ info: DropInfo) -> Int {
    let current = getCurrent()
    let frames = itemFramesProvider()
    let dict: [UUID: CGRect] = Dictionary(
      current.compactMap { item -> (UUID, CGRect)? in
        guard let id = item.id, let rect = frames[id] else { return nil }
        return (id, rect)
      },
      uniquingKeysWith: { first, _ in first }
    )
    return PlanningDropUtils.computeInsertionIndex(locationY: info.location.y, frames: dict)
  }
}
