import Foundation
import Testing
@testable import CosmicDaybook

/// The ParentLocker sign-in in the Keychain: the synced password and this
/// device's cookies saved, read back, replaced and deleted. Uses a made-up
/// site so it never meets a real sign-in.
@Suite("ParentLocker keychain", .serialized)
@MainActor
struct ParentLockerKeychainTests {

    private static let site = "keychain-tests.parentlocker.test"

    init() throws {
        try ParentLockerKeychain.deletePassword(site: Self.site)
        try ParentLockerKeychain.deleteCookies(site: Self.site)
    }

    @Test("The password round-trips, is replaced in place, and deletes")
    func passwordRoundTrip() throws {
        let typed = ParentLockerKeychain.Credential(email: "guide@school.test", password: "made-up-1")
        #expect(try ParentLockerKeychain.credential(site: Self.site) == nil)
        #expect(try !ParentLockerKeychain.hasPassword(site: Self.site))

        try ParentLockerKeychain.savePassword(typed, site: Self.site)
        #expect(try ParentLockerKeychain.credential(site: Self.site) == typed)
        #expect(try ParentLockerKeychain.hasPassword(site: Self.site))
        // The site as Settings may hold it reads as the same item.
        #expect(try ParentLockerKeychain.credential(site: "https://\(Self.site.uppercased())/sis/") == typed)

        let changed = ParentLockerKeychain.Credential(email: "guide2@school.test", password: "made-up-2")
        try ParentLockerKeychain.savePassword(changed, site: Self.site)
        #expect(try ParentLockerKeychain.credential(site: Self.site) == changed)

        try ParentLockerKeychain.deletePassword(site: Self.site)
        #expect(try ParentLockerKeychain.credential(site: Self.site) == nil)
        #expect(try !ParentLockerKeychain.hasPassword(site: Self.site))
        // Deleting again is fine.
        try ParentLockerKeychain.deletePassword(site: Self.site)
    }

    @Test("When the password was saved reads without the password, and goes with it")
    func passwordModified() throws {
        #expect(try ParentLockerKeychain.passwordModified(site: Self.site) == nil)
        let typed = ParentLockerKeychain.Credential(email: "guide@school.test", password: "made-up-5")
        try ParentLockerKeychain.savePassword(typed, site: Self.site)
        let saved = try #require(try ParentLockerKeychain.passwordModified(site: Self.site))
        #expect(abs(saved.timeIntervalSinceNow) < 600)

        try ParentLockerKeychain.deletePassword(site: Self.site)
        #expect(try ParentLockerKeychain.passwordModified(site: Self.site) == nil)
    }

    @Test("The cookies round-trip, are replaced, and delete")
    func cookiesRoundTrip() throws {
        #expect(try ParentLockerKeychain.cookies(site: Self.site).isEmpty)
        let first = [
            ParentLockerCookie(name: "PHPSESSID", value: "one", domain: Self.site),
            ParentLockerCookie(
                name: "plRemember", value: "two", domain: ".parentlocker.test", path: "/sis",
                expiresDate: Date(timeIntervalSince1970: 1_900_000_000), isSecure: true, isHTTPOnly: false
            )
        ]
        try ParentLockerKeychain.saveCookies(first, site: Self.site)
        #expect(try ParentLockerKeychain.cookies(site: Self.site) == first)

        let second = [ParentLockerCookie(name: "PHPSESSID", value: "three", domain: Self.site)]
        try ParentLockerKeychain.saveCookies(second, site: Self.site)
        #expect(try ParentLockerKeychain.cookies(site: Self.site) == second)

        try ParentLockerKeychain.deleteCookies(site: Self.site)
        #expect(try ParentLockerKeychain.cookies(site: Self.site).isEmpty)
        // Saving none deletes them too.
        try ParentLockerKeychain.saveCookies(second, site: Self.site)
        try ParentLockerKeychain.saveCookies([], site: Self.site)
        #expect(try ParentLockerKeychain.cookies(site: Self.site).isEmpty)
    }

    @Test("Deleting the cookies leaves the password, and the other way round")
    func itemsAreSeparate() throws {
        let typed = ParentLockerKeychain.Credential(email: "aide@school.test", password: "made-up-3")
        try ParentLockerKeychain.savePassword(typed, site: Self.site)
        try ParentLockerKeychain.saveCookies([.init(name: "a", value: "b", domain: Self.site)], site: Self.site)
        try ParentLockerKeychain.deleteCookies(site: Self.site)
        #expect(try ParentLockerKeychain.credential(site: Self.site) == typed)
        try ParentLockerKeychain.saveCookies([.init(name: "a", value: "b", domain: Self.site)], site: Self.site)
        try ParentLockerKeychain.deletePassword(site: Self.site)
        #expect(try ParentLockerKeychain.cookies(site: Self.site).count == 1)
        try ParentLockerKeychain.deleteCookies(site: Self.site)
    }

    @Test("Neither a sign-in nor a cookie shows its secret when printed")
    func descriptionsHideSecrets() {
        let credential = ParentLockerKeychain.Credential(email: "guide@school.test", password: "made-up-4")
        for text in [String(describing: credential), String(reflecting: credential), "\(credential)"] {
            #expect(!text.contains("made-up-4"))
            #expect(!text.contains("guide@school.test"))
        }
        let cookie = ParentLockerCookie(name: "PHPSESSID", value: "secret-value", domain: Self.site)
        #expect(!String(describing: cookie).contains("secret-value"))
    }
}
