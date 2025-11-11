//
//  MessageTypes.swift
//  SharedMessaging
//
//  Production-grade message types for inter-daemon communication
//

import Foundation
import PubNubSDK

// MARK: - Base Message Protocol
public protocol BaseMessage: Codable, Sendable {
    var id: UUID { get }
    var timestamp: Date { get }
    var messageType: MessageType { get }
    var source: DaemonType { get }
    var target: DaemonType? { get }
}

// MARK: - Message Type Enumeration
public enum MessageType: String, Codable, CaseIterable, Sendable {
    case heartbeat = "heartbeat"
    case systemStatus = "system_status"
    case userActivity = "user_activity"
    case configuration = "configuration"
    case command = "command"
    case response = "response"
    case error = "error"
    case shutdown = "shutdown"
}

// MARK: - Daemon Type Enumeration
public enum DaemonType: String, Codable, CaseIterable, Sendable {
    case user = "user_daemon"
    case system = "system_daemon"
    case broadcast = "broadcast"
}

// MARK: - Priority Levels
public enum MessagePriority: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case normal = "normal" 
    case high = "high"
    case critical = "critical"
}

// MARK: - Concrete Message Types

public struct HeartbeatMessage: BaseMessage {
    public let id: UUID
    public let timestamp: Date
    public let messageType: MessageType = .heartbeat
    public let source: DaemonType
    public let target: DaemonType?
    public let systemLoad: Double?
    public let memoryUsage: Double?
    public let uptime: TimeInterval

    public init(source: DaemonType, target: DaemonType? = nil, systemLoad: Double? = nil, memoryUsage: Double? = nil, uptime: TimeInterval) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.target = target
        self.systemLoad = systemLoad
        self.memoryUsage = memoryUsage
        self.uptime = uptime
    }
}

public struct SystemStatusMessage: BaseMessage {
    public let id: UUID
    public let timestamp: Date
    public let messageType: MessageType = .systemStatus
    public let source: DaemonType
    public let target: DaemonType?
    public let status: SystemStatus
    public let details: [String: String]?

    public init(source: DaemonType, target: DaemonType? = nil, status: SystemStatus, details: [String: String]? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.target = target
        self.status = status
        self.details = details
    }
}

public enum SystemStatus: String, Codable, Sendable {
    case healthy = "healthy"
    case degraded = "degraded"
    case critical = "critical"
    case maintenance = "maintenance"
}

public struct CommandMessage: BaseMessage {
    public let id: UUID
    public let timestamp: Date
    public let messageType: MessageType = .command
    public let source: DaemonType
    public let target: DaemonType?
    public let command: String
    public let parameters: [String: String]?
    public let priority: MessagePriority
    public let requiresResponse: Bool

    public init(source: DaemonType, target: DaemonType? = nil, command: String, parameters: [String: String]? = nil, priority: MessagePriority = .normal, requiresResponse: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.target = target
        self.command = command
        self.parameters = parameters
        self.priority = priority
        self.requiresResponse = requiresResponse
    }
}

public struct ResponseMessage: BaseMessage {
    public let id: UUID
    public let timestamp: Date
    public let messageType: MessageType = .response
    public let source: DaemonType
    public let target: DaemonType?
    public let correlationId: UUID
    public let success: Bool
    public let result: String?
    public let errorMessage: String?

    public init(source: DaemonType, target: DaemonType? = nil, correlationId: UUID, success: Bool, result: String? = nil, errorMessage: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.target = target
        self.correlationId = correlationId
        self.success = success
        self.result = result
        self.errorMessage = errorMessage
    }
}

// MARK: - Message Wrapper for PubNub
public struct PubSubMessage: Codable {
    public let messageType: MessageType
    public let payload: Data
    public let priority: MessagePriority
    public let source: DaemonType
    public let target: DaemonType?

    public init<T: BaseMessage>(message: T, priority: MessagePriority = .normal) throws {
        self.messageType = message.messageType
        self.payload = try JSONEncoder().encode(message)
        self.priority = priority
        self.source = message.source
        self.target = message.target
    }

    public func decode<T: BaseMessage>(as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: payload)
    }
}
