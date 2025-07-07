# Create the shared messaging library components

# 1. Message Types
message_types_swift = '''//
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
public enum MessageType: String, Codable, CaseIterable {
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
public enum DaemonType: String, Codable, CaseIterable {
    case user = "user_daemon"
    case system = "system_daemon"
    case broadcast = "broadcast"
}

// MARK: - Priority Levels
public enum MessagePriority: String, Codable, CaseIterable {
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

public enum SystemStatus: String, Codable {
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
'''

# 2. Configuration Management
configuration_swift = '''//
//  Configuration.swift
//  SharedMessaging
//
//  Configuration management for the dual daemon system
//

import Foundation

public struct AppConfiguration: Codable {
    public let pubSubConfig: PubSubConfiguration
    public let loggingConfig: LoggingConfiguration
    public let securityConfig: SecurityConfiguration
    
    public init(pubSubConfig: PubSubConfiguration, loggingConfig: LoggingConfiguration, securityConfig: SecurityConfiguration) {
        self.pubSubConfig = pubSubConfig
        self.loggingConfig = loggingConfig
        self.securityConfig = securityConfig
    }
    
    // Default configuration
    public static let `default` = AppConfiguration(
        pubSubConfig: .default,
        loggingConfig: .default,
        securityConfig: .default
    )
}

public struct PubSubConfiguration: Codable {
    public let publishKey: String
    public let subscribeKey: String
    public let userId: String
    public let channels: ChannelConfiguration
    public let connectionTimeout: TimeInterval
    public let heartbeatInterval: TimeInterval
    public let presenceTimeout: TimeInterval
    
    public init(publishKey: String, subscribeKey: String, userId: String, channels: ChannelConfiguration, connectionTimeout: TimeInterval = 10.0, heartbeatInterval: TimeInterval = 30.0, presenceTimeout: TimeInterval = 300.0) {
        self.publishKey = publishKey
        self.subscribeKey = subscribeKey
        self.userId = userId
        self.channels = channels
        self.connectionTimeout = connectionTimeout
        self.heartbeatInterval = heartbeatInterval
        self.presenceTimeout = presenceTimeout
    }
    
    public static let `default` = PubSubConfiguration(
        publishKey: ProcessInfo.processInfo.environment["PUBNUB_PUBLISH_KEY"] ?? "demo",
        subscribeKey: ProcessInfo.processInfo.environment["PUBNUB_SUBSCRIBE_KEY"] ?? "demo",
        userId: ProcessInfo.processInfo.environment["PUBNUB_USER_ID"] ?? UUID().uuidString,
        channels: .default
    )
}

public struct ChannelConfiguration: Codable {
    public let systemChannel: String
    public let userChannel: String
    public let heartbeatChannel: String
    public let commandChannel: String
    public let statusChannel: String
    
    public init(systemChannel: String, userChannel: String, heartbeatChannel: String, commandChannel: String, statusChannel: String) {
        self.systemChannel = systemChannel
        self.userChannel = userChannel
        self.heartbeatChannel = heartbeatChannel
        self.commandChannel = commandChannel
        self.statusChannel = statusChannel
    }
    
    public static let `default` = ChannelConfiguration(
        systemChannel: "dualdaemon.system",
        userChannel: "dualdaemon.user",
        heartbeatChannel: "dualdaemon.heartbeat",
        commandChannel: "dualdaemon.command",
        statusChannel: "dualdaemon.status"
    )
}

public struct LoggingConfiguration: Codable {
    public let logLevel: LogLevel
    public let logToFile: Bool
    public let logFilePath: String?
    public let maxLogFileSize: Int
    public let logRotationCount: Int
    
    public init(logLevel: LogLevel, logToFile: Bool, logFilePath: String?, maxLogFileSize: Int = 10_485_760, logRotationCount: Int = 5) {
        self.logLevel = logLevel
        self.logToFile = logToFile
        self.logFilePath = logFilePath
        self.maxLogFileSize = maxLogFileSize
        self.logRotationCount = logRotationCount
    }
    
    public static let `default` = LoggingConfiguration(
        logLevel: .info,
        logToFile: true,
        logFilePath: "/var/log/dualdaemon"
    )
}

public enum LogLevel: String, Codable, CaseIterable {
    case trace = "trace"
    case debug = "debug"
    case info = "info"
    case notice = "notice"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

public struct SecurityConfiguration: Codable {
    public let enableEncryption: Bool
    public let encryptionKey: String?
    public let allowedSources: [String]?
    public let requireSignatures: Bool
    
    public init(enableEncryption: Bool, encryptionKey: String?, allowedSources: [String]?, requireSignatures: Bool) {
        self.enableEncryption = enableEncryption
        self.encryptionKey = encryptionKey
        self.allowedSources = allowedSources
        self.requireSignatures = requireSignatures
    }
    
    public static let `default` = SecurityConfiguration(
        enableEncryption: true,
        encryptionKey: ProcessInfo.processInfo.environment["DUALDAEMON_ENCRYPTION_KEY"],
        allowedSources: nil,
        requireSignatures: false
    )
}

// MARK: - Configuration Manager
public final class ConfigurationManager: @unchecked Sendable {
    public static let shared = ConfigurationManager()
    
    private var _configuration: AppConfiguration
    private let lock = NSLock()
    
    public var configuration: AppConfiguration {
        lock.withLock { _configuration }
    }
    
    private init() {
        self._configuration = .default
        loadConfiguration()
    }
    
    public func updateConfiguration(_ config: AppConfiguration) {
        lock.withLock {
            _configuration = config
        }
        saveConfiguration()
    }
    
    private func loadConfiguration() {
        guard let configPath = configurationPath(),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return
        }
        
        lock.withLock {
            _configuration = config
        }
    }
    
    private func saveConfiguration() {
        guard let configPath = configurationPath(),
              let data = try? JSONEncoder().encode(_configuration) else {
            return
        }
        
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
    
    private func configurationPath() -> String? {
        let configDir = "/etc/dualdaemon"
        let configFile = "\\(configDir)/config.json"
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        
        return configFile
    }
}
'''

# Save the files
with open("MessageTypes.swift", "w") as f:
    f.write(message_types_swift)

with open("Configuration.swift", "w") as f:
    f.write(configuration_swift)

print("Created SharedMessaging library files:")
print("✅ MessageTypes.swift")
print("✅ Configuration.swift")
print("\nNext: Creating PubSubManager and Logger...")