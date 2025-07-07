# Create PubSubManager and Logger components

# 3. PubSubManager - Main messaging component
pubsub_manager_swift = '''//
//  PubSubManager.swift
//  SharedMessaging
//
//  Production-grade PubNub-based messaging manager
//

import Foundation
import PubNubSDK
import Logging

public protocol PubSubManagerDelegate: AnyObject {
    func pubSubManager(_ manager: PubSubManager, didReceiveMessage message: any BaseMessage)
    func pubSubManager(_ manager: PubSubManager, didReceiveError error: Error)
    func pubSubManager(_ manager: PubSubManager, didUpdateConnectionStatus status: ConnectionStatus)
}

public enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(Error)
}

@MainActor
public final class PubSubManager: ObservableObject {
    
    // MARK: - Properties
    private var pubnub: PubNub?
    private let configuration: PubSubConfiguration
    private let daemonType: DaemonType
    private let logger: Logger
    
    @Published public private(set) var connectionStatus: ConnectionStatus = .disconnected
    @Published public private(set) var subscribedChannels: Set<String> = []
    
    public weak var delegate: PubSubManagerDelegate?
    
    private var heartbeatTimer: Timer?
    private let messageQueue = DispatchQueue(label: "com.dualdaemon.messaging", qos: .userInitiated)
    private var pendingResponses: [UUID: (ResponseMessage) -> Void] = [:]
    
    // MARK: - Initialization
    public init(configuration: PubSubConfiguration, daemonType: DaemonType, logger: Logger) {
        self.configuration = configuration
        self.daemonType = daemonType
        self.logger = logger
        
        setupPubNub()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Setup
    private func setupPubNub() {
        let pubNubConfig = PubNubConfiguration(
            publishKey: configuration.publishKey,
            subscribeKey: configuration.subscribeKey,
            userId: configuration.userId
        )
        
        // Configure additional settings
        pubNubConfig.heartbeatInterval = UInt(configuration.heartbeatInterval)
        pubNubConfig.presenceTimeout = UInt(configuration.presenceTimeout)
        pubNubConfig.supressLeaveEvents = false
        pubNubConfig.requestMessageCountThreshold = 100
        
        pubnub = PubNub(configuration: pubNubConfig)
        
        // Add event listeners
        pubnub?.add(self)
        
        logger.info("PubNub configured for daemon type: \\(daemonType.rawValue)")
    }
    
    // MARK: - Connection Management
    public func connect() async throws {
        guard let pubnub = pubnub else {
            throw PubSubError.notConfigured
        }
        
        updateConnectionStatus(.connecting)
        logger.info("Connecting to PubNub...")
        
        do {
            // Subscribe to relevant channels based on daemon type
            let channels = getChannelsForDaemonType()
            
            pubnub.subscribe(to: channels)
            
            subscribedChannels = Set(channels)
            updateConnectionStatus(.connected)
            
            logger.info("Successfully connected and subscribed to channels: \\(channels)")
            
            // Start heartbeat
            startHeartbeat()
            
            // Send initial presence
            try await sendHeartbeat()
            
        } catch {
            updateConnectionStatus(.failed(error))
            logger.error("Failed to connect: \\(error)")
            throw error
        }
    }
    
    public func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        pubnub?.unsubscribeAll()
        pubnub?.removeAllListeners()
        
        subscribedChannels.removeAll()
        updateConnectionStatus(.disconnected)
        
        logger.info("Disconnected from PubNub")
    }
    
    private func getChannelsForDaemonType() -> [String] {
        let channels = configuration.channels
        
        switch daemonType {
        case .user:
            return [
                channels.userChannel,
                channels.heartbeatChannel,
                channels.commandChannel,
                channels.statusChannel
            ]
        case .system:
            return [
                channels.systemChannel,
                channels.heartbeatChannel,
                channels.commandChannel,
                channels.statusChannel
            ]
        case .broadcast:
            return [
                channels.systemChannel,
                channels.userChannel,
                channels.heartbeatChannel,
                channels.commandChannel,
                channels.statusChannel
            ]
        }
    }
    
    // MARK: - Message Publishing
    public func publish<T: BaseMessage>(message: T, to channel: String? = nil) async throws {
        guard let pubnub = pubnub else {
            throw PubSubError.notConfigured
        }
        
        let targetChannel = channel ?? getDefaultChannelForMessage(message)
        let pubSubMessage = try PubSubMessage(message: message)
        
        logger.debug("Publishing message of type \\(message.messageType.rawValue) to channel \\(targetChannel)")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pubnub.publish(
                channel: targetChannel,
                message: pubSubMessage
            ) { result in
                switch result {
                case .success:
                    self.logger.debug("Message published successfully")
                    continuation.resume()
                case .failure(let error):
                    self.logger.error("Failed to publish message: \\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func publishAndWaitForResponse<T: BaseMessage>(
        command: CommandMessage,
        to channel: String? = nil,
        timeout: TimeInterval = 30.0
    ) async throws -> ResponseMessage {
        
        return try await withCheckedThrowingContinuation { continuation in
            // Store the continuation for when we receive the response
            pendingResponses[command.id] = { response in
                continuation.resume(returning: response)
            }
            
            // Set timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if self.pendingResponses.removeValue(forKey: command.id) != nil {
                    continuation.resume(throwing: PubSubError.timeout)
                }
            }
            
            // Publish the command
            Task {
                do {
                    try await self.publish(message: command, to: channel)
                } catch {
                    self.pendingResponses.removeValue(forKey: command.id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Heartbeat Management
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: configuration.heartbeatInterval, repeats: true) { _ in
            Task {
                try? await self.sendHeartbeat()
            }
        }
    }
    
    private func sendHeartbeat() async throws {
        let uptime = ProcessInfo.processInfo.systemUptime
        let heartbeat = HeartbeatMessage(
            source: daemonType,
            systemLoad: getSystemLoad(),
            memoryUsage: getMemoryUsage(),
            uptime: uptime
        )
        
        try await publish(message: heartbeat, to: configuration.channels.heartbeatChannel)
    }
    
    // MARK: - Utility Methods
    private func getDefaultChannelForMessage<T: BaseMessage>(_ message: T) -> String {
        let channels = configuration.channels
        
        switch message.messageType {
        case .heartbeat:
            return channels.heartbeatChannel
        case .systemStatus:
            return channels.statusChannel
        case .command, .response:
            return channels.commandChannel
        case .userActivity:
            return channels.userChannel
        default:
            return daemonType == .user ? channels.userChannel : channels.systemChannel
        }
    }
    
    private func updateConnectionStatus(_ status: ConnectionStatus) {
        Task { @MainActor in
            connectionStatus = status
            delegate?.pubSubManager(self, didUpdateConnectionStatus: status)
        }
    }
    
    private func getSystemLoad() -> Double? {
        // Implement system load calculation for macOS
        var loadavg: [Double] = [0, 0, 0]
        if getloadavg(&loadavg, 3) != -1 {
            return loadavg[0]
        }
        return nil
    }
    
    private func getMemoryUsage() -> Double? {
        // Implement memory usage calculation for macOS
        let task = mach_task_self_
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(task, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }
        return nil
    }
}

// MARK: - PubNub Event Listener
extension PubSubManager: EventListener {
    public func client(_ client: PubNub, didReceive message: PubNubMessage) {
        messageQueue.async {
            self.handleReceivedMessage(message)
        }
    }
    
    public func client(_ client: PubNub, didReceiveSubscription event: SubscriptionEvent) {
        switch event {
        case .connectionStatusChanged(let status):
            handleConnectionStatusChange(status)
        case .subscribeError(let error):
            logger.error("Subscription error: \\(error)")
            Task { @MainActor in
                delegate?.pubSubManager(self, didReceiveError: error)
            }
        default:
            break
        }
    }
    
    private func handleReceivedMessage(_ message: PubNubMessage) {
        do {
            guard let messageData = message.payload.jsonStringify?.data(using: .utf8),
                  let pubSubMessage = try? JSONDecoder().decode(PubSubMessage.self, from: messageData) else {
                logger.warning("Failed to decode message payload")
                return
            }
            
            // Skip messages from ourselves
            if pubSubMessage.source == daemonType {
                return
            }
            
            let decodedMessage = try decodeMessage(pubSubMessage)
            
            logger.debug("Received message of type \\(decodedMessage.messageType.rawValue) from \\(decodedMessage.source.rawValue)")
            
            // Handle responses to pending commands
            if let responseMessage = decodedMessage as? ResponseMessage,
               let responseHandler = pendingResponses.removeValue(forKey: responseMessage.correlationId) {
                responseHandler(responseMessage)
                return
            }
            
            Task { @MainActor in
                delegate?.pubSubManager(self, didReceiveMessage: decodedMessage)
            }
            
        } catch {
            logger.error("Failed to process received message: \\(error)")
        }
    }
    
    private func decodeMessage(_ pubSubMessage: PubSubMessage) throws -> any BaseMessage {
        switch pubSubMessage.messageType {
        case .heartbeat:
            return try pubSubMessage.decode(as: HeartbeatMessage.self)
        case .systemStatus:
            return try pubSubMessage.decode(as: SystemStatusMessage.self)
        case .command:
            return try pubSubMessage.decode(as: CommandMessage.self)
        case .response:
            return try pubSubMessage.decode(as: ResponseMessage.self)
        default:
            throw PubSubError.unsupportedMessageType(pubSubMessage.messageType)
        }
    }
    
    private func handleConnectionStatusChange(_ status: ConnectionStatus) {
        switch status {
        case .connected:
            updateConnectionStatus(.connected)
        case .disconnected:
            updateConnectionStatus(.disconnected)
        case .reconnecting:
            updateConnectionStatus(.reconnecting)
        case .connectionError(let error):
            updateConnectionStatus(.failed(error))
        default:
            break
        }
    }
}

// MARK: - Error Types
public enum PubSubError: Error, LocalizedError {
    case notConfigured
    case timeout
    case unsupportedMessageType(MessageType)
    case publishFailed(Error)
    case subscriptionFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "PubNub is not properly configured"
        case .timeout:
            return "Operation timed out"
        case .unsupportedMessageType(let type):
            return "Unsupported message type: \\(type.rawValue)"
        case .publishFailed(let error):
            return "Failed to publish message: \\(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Failed to subscribe: \\(error.localizedDescription)"
        }
    }
}
'''

# 4. Logger utility
logger_swift = '''//
//  Logger.swift
//  SharedMessaging
//
//  Centralized logging for the dual daemon system
//

import Foundation
import Logging
import os.log

public final class DaemonLogger {
    
    private let osLogger: OSLog
    private let swiftLogger: Logger
    private let configuration: LoggingConfiguration
    private let daemonType: DaemonType
    
    public init(daemonType: DaemonType, configuration: LoggingConfiguration) {
        self.daemonType = daemonType
        self.configuration = configuration
        
        // Setup OS Logger
        self.osLogger = OSLog(subsystem: "com.dualdaemon.\\(daemonType.rawValue)", category: "general")
        
        // Setup Swift Logger
        var logger = Logger(label: "dualdaemon.\\(daemonType.rawValue)")
        logger.logLevel = configuration.logLevel.swiftLogLevel
        self.swiftLogger = logger
        
        // Setup file logging if enabled
        if configuration.logToFile {
            setupFileLogging()
        }
    }
    
    private func setupFileLogging() {
        guard let logPath = configuration.logFilePath else { return }
        
        let logDirectory = URL(fileURLWithPath: logPath)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        
        // Create log file path for this daemon
        let logFile = logDirectory.appendingPathComponent("\\(daemonType.rawValue).log")
        
        // Setup log rotation if file is too large
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let fileSize = attributes[.size] as? Int,
           fileSize > configuration.maxLogFileSize {
            rotateLogFile(logFile)
        }
    }
    
    private func rotateLogFile(_ logFile: URL) {
        for i in (1..<configuration.logRotationCount).reversed() {
            let oldFile = logFile.appendingPathExtension("\\(i)")
            let newFile = logFile.appendingPathExtension("\\(i + 1)")
            
            if FileManager.default.fileExists(atPath: oldFile.path) {
                try? FileManager.default.moveItem(at: oldFile, to: newFile)
            }
        }
        
        // Move current log to .1
        let firstRotation = logFile.appendingPathExtension("1")
        try? FileManager.default.moveItem(at: logFile, to: firstRotation)
    }
    
    // MARK: - Logging Methods
    public func trace(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .trace, message: message, file: file, function: function, line: line)
    }
    
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }
    
    public func notice(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .notice, message: message, file: file, function: function, line: line)
    }
    
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message: message, file: file, function: function, line: line)
    }
    
    public func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .critical, message: message, file: file, function: function, line: line)
    }
    
    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let formattedMessage = "[\\(daemonType.rawValue)] \\(filename):\\(line) \\(function) - \\(message)"
        
        // Log to Swift Logger
        swiftLogger.log(level: level.swiftLogLevel, Logger.Message(stringLiteral: formattedMessage))
        
        // Log to OS Logger
        let osLogType = level.osLogType
        os_log("%{public}@", log: osLogger, type: osLogType, formattedMessage)
        
        // Log to file if enabled
        if configuration.logToFile {
            logToFile(level: level, message: formattedMessage)
        }
    }
    
    private func logToFile(level: LogLevel, message: String) {
        guard let logPath = configuration.logFilePath else { return }
        
        let logDirectory = URL(fileURLWithPath: logPath)
        let logFile = logDirectory.appendingPathComponent("\\(daemonType.rawValue).log")
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\\(timestamp)] [\\(level.rawValue.uppercased())] \\(message)\\n"
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
}

// MARK: - LogLevel Extensions
extension LogLevel {
    var swiftLogLevel: Logger.Level {
        switch self {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info, .notice: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

// MARK: - Logger Protocol Conformance
extension DaemonLogger: LogHandler {
    public var logLevel: Logger.Level {
        get { swiftLogger.logLevel }
        set { /* Cannot set on our wrapper */ }
    }
    
    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { swiftLogger[metadataKey: metadataKey] }
        set { /* Cannot set on our wrapper */ }
    }
    
    public var metadata: Logger.Metadata {
        get { swiftLogger.metadata }
        set { /* Cannot set on our wrapper */ }
    }
    
    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        self.log(level: LogLevel.from(swiftLevel: level), message: message.description, file: file, function: function, line: Int(line))
    }
}

extension LogLevel {
    static func from(swiftLevel: Logger.Level) -> LogLevel {
        switch swiftLevel {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}
'''

# Save the files
with open("PubSubManager.swift", "w") as f:
    f.write(pubsub_manager_swift)

with open("Logger.swift", "w") as f:
    f.write(logger_swift)

print("✅ PubSubManager.swift")
print("✅ Logger.swift")
print("\nSharedMessaging library completed!")
print("Next: Creating daemon implementations...")