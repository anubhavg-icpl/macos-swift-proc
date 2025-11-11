import XCTest
@testable import SharedMessaging

final class MessageTypesTests: XCTestCase {
    
    func testHeartbeatMessageSerialization() throws {
        let message = HeartbeatMessage(
            source: .user,
            target: .system,
            systemLoad: 0.5,
            memoryUsage: 1024.0,
            uptime: 3600.0
        )
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(HeartbeatMessage.self, from: encoded)
        
        XCTAssertEqual(message.id, decoded.id)
        XCTAssertEqual(message.source, decoded.source)
        XCTAssertEqual(message.target, decoded.target)
        XCTAssertEqual(message.systemLoad, decoded.systemLoad)
        XCTAssertEqual(message.memoryUsage, decoded.memoryUsage)
        XCTAssertEqual(message.uptime, decoded.uptime)
    }
    
    func testCommandMessageSerialization() throws {
        let message = CommandMessage(
            source: .system,
            target: .user,
            command: "restart",
            parameters: ["service": "test"],
            priority: .high,
            requiresResponse: true
        )
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(CommandMessage.self, from: encoded)
        
        XCTAssertEqual(message.command, decoded.command)
        XCTAssertEqual(message.parameters, decoded.parameters)
        XCTAssertEqual(message.priority, decoded.priority)
        XCTAssertEqual(message.requiresResponse, decoded.requiresResponse)
    }
    
    func testResponseMessageSerialization() throws {
        let correlationId = UUID()
        let message = ResponseMessage(
            source: .user,
            target: .system,
            correlationId: correlationId,
            success: true,
            result: "completed",
            errorMessage: nil
        )
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ResponseMessage.self, from: encoded)
        
        XCTAssertEqual(message.correlationId, decoded.correlationId)
        XCTAssertEqual(message.success, decoded.success)
        XCTAssertEqual(message.result, decoded.result)
        XCTAssertNil(decoded.errorMessage)
    }
    
    func testPubSubMessageWrapper() throws {
        let heartbeat = HeartbeatMessage(
            source: .user,
            systemLoad: 0.3,
            memoryUsage: 512.0,
            uptime: 1800.0
        )
        
        let wrapper = try PubSubMessage(message: heartbeat, priority: .normal)
        
        XCTAssertEqual(wrapper.messageType, .heartbeat)
        XCTAssertEqual(wrapper.priority, .normal)
        XCTAssertEqual(wrapper.source, .user)
        
        let decoded = try wrapper.decode(as: HeartbeatMessage.self)
        XCTAssertEqual(heartbeat.id, decoded.id)
        XCTAssertEqual(heartbeat.uptime, decoded.uptime)
    }
}
