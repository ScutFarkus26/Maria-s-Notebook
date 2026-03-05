import SwiftUI

public struct ParsingOverlay: View {
    @Binding var isParsing: Bool
    var onCancel: (() -> Void)?
    
    public var body: some View {
        if isParsing {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView("Parsing…")
                    
                    if let onCancel = onCancel {
                        Button("Cancel", action: onCancel)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ParsingOverlay_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isParsing = true
        
        var body: some View {
            ParsingOverlay(isParsing: $isParsing, onCancel: {
                isParsing = false
            })
        }
    }
    
    static var previews: some View {
        PreviewWrapper()
    }
}
