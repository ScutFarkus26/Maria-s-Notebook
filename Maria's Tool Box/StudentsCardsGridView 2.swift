import SwiftUI

struct StudentsCardsGridView_Sample: View {
    var body: some View {
        Text("Hello, World!")
    }
}

struct StudentsCardsGridView_Sample_Previews: PreviewProvider {
    static var previews: some View {
        StudentsCardsGridView_Sample()
    }
}

extension Date {
    func startOfMonth() -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: comps)!
    }
}
