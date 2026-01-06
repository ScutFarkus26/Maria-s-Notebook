import Foundation
import Observation
import SwiftData

@Observable
final class MeetingsAgendaViewModel {
    var startDate: Date = Date()
    var scrollToDay: Date? = nil
    private let calendar = Calendar.current
    
    // Add context reference to fetch data
    var modelContext: ModelContext? = nil

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
    
    // New helper to fetch meetings for a specific day
    func meetings(for date: Date) -> [StudentMeeting] {
        guard let modelContext else { return [] }
        
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        
        // Predicate to find meetings in this 24hr window
        let predicate = #Predicate<StudentMeeting> { meeting in
            meeting.date >= start && meeting.date < end
        }
        
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.date)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
