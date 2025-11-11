//
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

    public static let `default`: PubSubConfiguration = {
        guard let publishKey = ProcessInfo.processInfo.environment["PUBNUB_PUBLISH_KEY"],
              let subscribeKey = ProcessInfo.processInfo.environment["PUBNUB_SUBSCRIBE_KEY"],
              !publishKey.isEmpty,
              !subscribeKey.isEmpty else {
            fatalError("""
                FATAL: PubNub credentials not configured. 
                Set PUBNUB_PUBLISH_KEY and PUBNUB_SUBSCRIBE_KEY environment variables.
                Production systems MUST NOT use demo credentials.
                """)
        }
        
        let userId = ProcessInfo.processInfo.environment["PUBNUB_USER_ID"] ?? UUID().uuidString
        
        return PubSubConfiguration(
            publishKey: publishKey,
            subscribeKey: subscribeKey,
            userId: userId,
            channels: .default
        )
    }()
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

    public static let `default`: SecurityConfiguration = {
        let enableEncryption = ProcessInfo.processInfo.environment["DUALDAEMON_DISABLE_ENCRYPTION"] != "true"
        let encryptionKey = ProcessInfo.processInfo.environment["DUALDAEMON_ENCRYPTION_KEY"]
        
        if enableEncryption && (encryptionKey == nil || encryptionKey?.isEmpty == true) {
            fatalError("""
                FATAL: Encryption is enabled but no encryption key provided.
                Set DUALDAEMON_ENCRYPTION_KEY environment variable or disable encryption.
                WARNING: Disabling encryption is NOT recommended for production.
                """)
        }
        
        return SecurityConfiguration(
            enableEncryption: enableEncryption,
            encryptionKey: encryptionKey,
            allowedSources: nil,
            requireSignatures: false
        )
    }()
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
        let configFile = "\(configDir)/config.json"

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        return configFile
    }
}
