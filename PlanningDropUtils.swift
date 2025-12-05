import Foundation
import CoreGraphics

enum PlanningDropUtils {
    static func computeInsertionIndex(locationY: CGFloat, frames: [UUID: CGRect]) -> Int {
        let ordered = frames.sorted { $0.value.minY < $1.value.minY }
        for (index, frame) in ordered.enumerated() {
            let midY = frame.value.midY
            if locationY < midY {
                return index
            }
        }
        return ordered.count
    }
    
    static func reorderIDs(current: [UUID], moving: UUID, insertionIndex: Int) -> [UUID] {
        var ids = current
        if let currentIndex = ids.firstIndex(of: moving) {
            ids.remove(at: currentIndex)
        }
        let boundedIndex = max(0, min(insertionIndex, ids.count))
        ids.insert(moving, at: boundedIndex)
        return ids
    }
    
    static func assignSequentialTimes(ids: [UUID], base: Date, calendar: Calendar, spacingSeconds: Int) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for (idx, id) in ids.enumerated() {
            if let date = calendar.date(byAdding: .second, value: idx * spacingSeconds, to: base) {
                result[id] = date
            }
        }
        return result
    }
}
