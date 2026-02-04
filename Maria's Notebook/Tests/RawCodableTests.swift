#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

/// Tests for the @RawCodable property wrapper
@Suite("RawCodable Property Wrapper Tests")
struct RawCodableTests {
    
    // MARK: - Test Enums
    
    enum TestStatus: String, Codable, Sendable {
        case active
        case inactive
        case archived
    }
    
    enum TestPriority: String, Codable, Sendable {
        case low
        case medium
        case high
    }
    
    // MARK: - Test Model
    
    struct TestModel: Codable, Sendable {
        @RawCodable var status: TestStatus = .active
        @RawCodable var priority: TestPriority = .medium
        var name: String
    }
    
    // MARK: - Basic Functionality Tests
    
    @Test("Property wrapper stores and retrieves enum values correctly")
    func testBasicGetSet() {
        var model = TestModel(name: "Test")
        
        // Initial value should be the default
        #expect(model.status == .active)
        
        // Setting new value should work
        model.status = .inactive
        #expect(model.status == .inactive)
        
        model.status = .archived
        #expect(model.status == .archived)
    }
    
    @Test("Multiple wrapped properties work independently")
    func testMultipleProperties() {
        var model = TestModel(name: "Test")
        
        model.status = .inactive
        model.priority = .high
        
        #expect(model.status == .inactive)
        #expect(model.priority == .high)
        
        model.status = .active
        #expect(model.status == .active)
        #expect(model.priority == .high)
    }
    
    // MARK: - Codable Tests
    
    @Test("Property wrapper encodes to JSON correctly")
    func testEncoding() throws {
        let model = TestModel(name: "Test Item")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(model)
        let json = String(data: data, encoding: .utf8)!
        
        // Should encode as raw string value
        #expect(json.contains("\"status\":\"active\""))
        #expect(json.contains("\"priority\":\"medium\""))
        #expect(json.contains("\"name\":\"Test Item\""))
    }
    
    @Test("Property wrapper decodes from JSON correctly")
    func testDecoding() throws {
        let json = """
        {
            "name": "Test Item",
            "priority": "high",
            "status": "archived"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let model = try decoder.decode(TestModel.self, from: data)
        
        #expect(model.name == "Test Item")
        #expect(model.status == .archived)
        #expect(model.priority == .high)
    }
    
    @Test("Round-trip encoding and decoding preserves values")
    func testRoundTrip() throws {
        var original = TestModel(name: "Original")
        original.status = .inactive
        original.priority = .low
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TestModel.self, from: data)
        
        #expect(decoded.name == original.name)
        #expect(decoded.status == original.status)
        #expect(decoded.priority == original.priority)
    }
    
    // MARK: - Equatable & Hashable Tests
    
    @Test("Wrapped values support equality comparison")
    func testEquality() {
        let wrapper1 = RawCodable(wrappedValue: TestStatus.active)
        let wrapper2 = RawCodable(wrappedValue: TestStatus.active)
        let wrapper3 = RawCodable(wrappedValue: TestStatus.inactive)
        
        #expect(wrapper1 == wrapper2)
        #expect(wrapper1 != wrapper3)
    }
    
    @Test("Wrapped values support hashing")
    func testHashing() {
        let wrapper1 = RawCodable(wrappedValue: TestStatus.active)
        let wrapper2 = RawCodable(wrappedValue: TestStatus.active)
        let wrapper3 = RawCodable(wrappedValue: TestStatus.inactive)
        
        var hasher1 = Hasher()
        wrapper1.hash(into: &hasher1)
        
        var hasher2 = Hasher()
        wrapper2.hash(into: &hasher2)
        
        var hasher3 = Hasher()
        wrapper3.hash(into: &hasher3)
        
        // Same values should produce same hash (in same execution)
        #expect(hasher1.finalize() == hasher2.finalize())
        
        // Different values typically produce different hashes (not guaranteed, but likely)
        #expect(hasher1.finalize() != hasher3.finalize())
    }
    
    // MARK: - Integration Tests
    
    @Test("Property wrapper works with multiple enum types")
    func testMultipleEnumTypes() {
        struct MultiEnumModel: Codable {
            @RawCodable var status: TestStatus = .active
            @RawCodable var priority: TestPriority = .medium
        }
        
        var model = MultiEnumModel()
        model.status = .archived
        model.priority = .high
        
        #expect(model.status == .archived)
        #expect(model.priority == .high)
    }
    
    @Test("Property wrapper supports Sendable for concurrency")
    func testSendable() {
        let wrapper = RawCodable(wrappedValue: TestStatus.active)
        
        // Should compile without warnings about Sendable
        Task {
            let _ = wrapper.wrappedValue
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Property wrapper handles all enum cases")
    func testAllEnumCases() {
        var model = TestModel(name: "Test")
        
        for status in [TestStatus.active, .inactive, .archived] {
            model.status = status
            #expect(model.status == status)
        }
        
        for priority in [TestPriority.low, .medium, .high] {
            model.priority = priority
            #expect(model.priority == priority)
        }
    }
    
    @Test("Property wrapper default value is used on initialization")
    func testDefaultValue() {
        let model = TestModel(name: "Test")
        
        // Should use defaults specified in property declaration
        #expect(model.status == .active)
        #expect(model.priority == .medium)
    }
}

#endif
