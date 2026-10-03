import SwiftUI

/// Centers its content both ways in the space it is given.
struct Center<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack { Spacer(); HStack { Spacer(); content; Spacer() }; Spacer() }
    }
}
