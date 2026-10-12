import Testing
import Foundation

/// Checks the entitlements file that the app is signed with. App Review rejects a
/// build whose entitlements contain an entry set to false (guideline 2.4.5(i)), so
/// a permission the app does not use must be left out instead.
struct EntitlementsTests {

    private func entitlements() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Plainfile/Resources/Plainfile.entitlements")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func everyEntitlementIsTurnedOn() throws {
        for (key, value) in try entitlements() {
            #expect((value as? Bool) != false, "\(key) is set to false. Remove it instead.")
        }
    }

    @Test func onlySandboxAndUserSelectedFiles() throws {
        let keys = Set(try entitlements().keys)
        #expect(keys == ["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write"])
    }
}
