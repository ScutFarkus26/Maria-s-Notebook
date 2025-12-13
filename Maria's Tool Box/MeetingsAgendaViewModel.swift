import Foundation
import Observation

@Observable
final class MeetingsAgendaViewModel {
    var startDate: Date = Date()
    var scrollToDay: Date? = nil
    private let calendar = Calendar.current

    var days: [Date] {
        var result: [Date] = []
        var d = calendar.startOfDay(for: startDate)
        for _ in 0..<7 {
            result.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return result
    }

    func dayID(_ day: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    func move(by days: Int) {
        startDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
    }

    func resetToToday() {
        startDate = calendar.startOfDay(for: Date())
    }
}
