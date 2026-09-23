import Testing
import CoreGraphics
@testable import CosmicDaybook

// MARK: - Corner radius tokens
//
// Every radius the app draws with has one named case, and each case pins
// the value it stood in for when the literals were migrated (2026-09-22).
// A token that drifts would move every site that uses it at once, so the
// numbers are asserted here rather than trusted. `CardStyle.cornerRadius`
// is the card token, not a second copy of 12.

@Suite("Design tokens")
struct DesignTokensTests {

    @Test("Every CornerRadius case pins its migrated value")
    func cornerRadiusValues() {
        #expect(UIConstants.CornerRadius.hairline == 1)
        #expect(UIConstants.CornerRadius.tiny == 3)
        #expect(UIConstants.CornerRadius.small == 6)
        #expect(UIConstants.CornerRadius.medium == 8)
        #expect(UIConstants.CornerRadius.control == 10)
        #expect(UIConstants.CornerRadius.large == 12)
        #expect(UIConstants.CornerRadius.tile == 14)
        #expect(UIConstants.CornerRadius.extraLarge == 16)
        #expect(UIConstants.CornerRadius.hero == 20)
    }

    @Test("CornerRadius cases are distinct and ascending")
    func cornerRadiusOrdering() {
        let ladder: [CGFloat] = [
            UIConstants.CornerRadius.hairline,
            UIConstants.CornerRadius.tiny,
            UIConstants.CornerRadius.small,
            UIConstants.CornerRadius.medium,
            UIConstants.CornerRadius.control,
            UIConstants.CornerRadius.large,
            UIConstants.CornerRadius.tile,
            UIConstants.CornerRadius.extraLarge,
            UIConstants.CornerRadius.hero
        ]
        #expect(ladder == ladder.sorted())
        #expect(Set(ladder).count == ladder.count)
    }

    @Test("CardStyle.cornerRadius is the large token")
    @MainActor
    func cardStyleUsesLargeToken() {
        #expect(CardStyle.cornerRadius == UIConstants.CornerRadius.large)
        #expect(CardStyle.cornerRadius == 12)
    }
}
