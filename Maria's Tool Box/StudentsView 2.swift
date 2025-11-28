import SwiftUI

struct ExampleView: View {
    @State private var selection: Int = 0
    @State private var count: Int = 0
    
    var body: some View {
        VStack {
            Picker("Options", selection: $selection) {
                Text("One").tag(1)
                Text("Two").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selection) { _, newValue in
                print("Selection changed to \(newValue)")
            }
            
            Button("Increment") {
                count += 1
            }
            .onChange(of: count) {
                print("Count changed")
            }
        }
    }
}

struct ExampleView_Previews: PreviewProvider {
    static var previews: some View {
        ExampleView()
    }
}
