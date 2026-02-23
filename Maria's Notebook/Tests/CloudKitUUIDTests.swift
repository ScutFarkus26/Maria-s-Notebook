#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("CloudKitUUID Property Wrapper Tests")
struct CloudKitUUIDTests {
    
    // MARK: - Test Model
    
    struct TestModel: Codable {
        @CloudKitUUID var requiredID: UUID = UUID()
        var optionalID: UUID? = nil  // Regular optional, not wrapped
        var name: String
    }
    
    // MARK: - Basic Functionality Tests
    
    @Test("CloudKitUUID stores and retrieves UUID correctly")
    func testBasicGetSet() {
        var model = TestModel(name: "Test")
        let originalID = model.requiredID
        
        let newID = UUID()
        model.requiredID = newID
        #expect(model.requiredID == newID)
        #expect(model.requiredID != originalID)
    }
    
    @Test("CloudKitUUID projected value provides String access")
    func testProjectedValue() {
        let testUUID = UUID()
        var model = TestModel(name: "Test")
        model.requiredID = testUUID
        
        // Projected value should give us the string
        let stringValue = model.$requiredID
        #expect(stringValue == testUUID.uuidString)
    }
    
    @Test("Optional UUID handles nil correctly")
    func testOptionalNil() {
        var model = TestModel(name: "Test")
        model.optionalID = nil
        
        #expect(model.optionalID == nil)
    }
    
    @Test("Optional UUID handles UUID correctly")
    func testOptionalWithValue() {
        var model = TestModel(name: "Test")
        let testUUID = UUID()
        model.optionalID = testUUID
        
        #expect(model.optionalID == testUUID)
    }
    
    // MARK: - Codable Tests
    
    @Test("CloudKitUUID encodes to JSON as string")
    func testEncoding() throws {
        let testUUID = UUID()
        var model = TestModel(name: "Test Item")
        model.requiredID = testUUID
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(model)
        let json = String(data: data, encoding: .utf8)!
        
        #expect(json.contains(testUUID.uuidString))
        #expect(json.contains("\"name\":\"Test Item\""))
    }
    
    @Test("CloudKitUUID decodes from JSON string")
    func testDecoding() throws {
        let testUUID = UUID()
        let json = """
        {
            "name": "Test Item",
            "requiredID": "\(testUUID.uuidString)",
            "optionalID": null
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let model = try decoder.decode(TestModel.self, from: data)
        
        #expect(model.name == "Test Item")
        #expect(model.requiredID == testUUID)
        #expect(model.optionalID == nil)
    }
    
    @Test("Round-trip encoding and decoding preserves UUIDs")
    func testRoundTrip() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        var original = TestModel(name: "Original")
        original.requiredID = uuid1
        original.optionalID = uuid2
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TestModel.self, from: data)
        
        #expect(decoded.name == original.name)
        #expect(decoded.requiredID == original.requiredID)
        #expect(decoded.optionalID == original.optionalID)
    }
    
    // MARK: - Invalid String Handling
    
    @Test("CloudKitUUID handles invalid string by generating new UUID")
    func testInvalidString() {
        let wrapper = CloudKitUUID(stringValue: "not-a-valid-uuid")
        let uuid = wrapper.wrappedValue
        
        // Should generate a new valid UUID, not crash
        #expect(uuid.uuidString.count == 36)
    }
    

    
    // MARK: - Hashable Tests
    
    @Test("CloudKitUUID supports hashing")
    func testHashing() {
        let uuid = UUID()
        let wrapper1 = CloudKitUUID(wrappedValue: uuid)
        let wrapper2 = CloudKitUUID(wrappedValue: uuid)
        let wrapper3 = CloudKitUUID(wrappedValue: UUID())
        
        #expect(wrapper1 == wrapper2)
        #expect(wrapper1 != wrapper3)
        
        var hasher1 = Hasher()
        wrapper1.hash(into: &hasher1)
        
        var hasher2 = Hasher()
        wrapper2.hash(into: &hasher2)
        
        #expect(hasher1.finalize() == hasher2.finalize())
    }
    
    // MARK: - Array Extension Tests
    
    @Test("UUID array converts to CloudKit strings")
    func testArrayToStrings() {
        let uuids = [UUID(), UUID(), UUID()]
        let strings = uuids.cloudKitStrings
        
        #expect(strings.count == 3)
        #expect(strings[0] == uuids[0].uuidString)
        #expect(strings[1] == uuids[1].uuidString)
        #expect(strings[2] == uuids[2].uuidString)
    }
    
    @Test("CloudKit strings convert to UUID array")
    func testStringsToArray() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let strings = [uuid1.uuidString, uuid2.uuidString]
        
        let uuids = Array<UUID>(cloudKitStrings: strings)
        
        #expect(uuids.count == 2)
        #expect(uuids[0] == uuid1)
        #expect(uuids[1] == uuid2)
    }
    
    @Test("CloudKit strings with invalid UUIDs are filtered")
    func testStringsWithInvalid() {
        let uuid = UUID()
        let strings = [uuid.uuidString, "invalid", "also-invalid"]
        
        let uuids = Array<UUID>(cloudKitStrings: strings)
        
        #expect(uuids.count == 1)
        #expect(uuids[0] == uuid)
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty string generates new UUID")
    func testEmptyString() {
        let wrapper = CloudKitUUID(stringValue: "")
        let uuid = wrapper.wrappedValue
        
        #expect(uuid.uuidString.count == 36)
        #expect(uuid.uuidString != "")
    }
    
    @Test("Multiple CloudKitUUID properties work independently")
    func testMultipleProperties() {
        var model = TestModel(name: "Test")
        let id1 = UUID()
        let id2 = UUID()
        
        model.requiredID = id1
        model.optionalID = id2
        
        #expect(model.requiredID == id1)
        #expect(model.optionalID == id2)
        #expect(model.requiredID != model.optionalID)
    }
    
    @Test("CloudKitUUID is Sendable for concurrency")
    func testSendable() {
        let wrapper = CloudKitUUID(wrappedValue: UUID())
        
        Task {
            let _ = wrapper.wrappedValue
        }
        
        // Test passes if it compiles without Sendable warnings
    }
}

#endif
