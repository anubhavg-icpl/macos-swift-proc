//
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
    
    // Thread-safe pending responses management with timeout tracking
    private let responsesLock = NSLock()
    private var pendingResponses: [UUID: PendingResponse] = [:]
    
    private struct PendingResponse {
        let handler: (ResponseMessage) -> Void
        let createdAt: Date
        let timeoutTask: Task<Void, Never>?
    }

    // MARK: - Initialization
    public init(configuration: PubSubConfiguration, daemonType: DaemonType, logger: Logger) {
        self.configuration = configuration
        self.daemonType = daemonType
        self.logger = logger

        setupPubNub()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.disconnect()
        }
    }

    // MARK: - Setup
    private func setupPubNub() {
        var pubNubConfig = PubNubConfiguration(
            publishKey: configuration.publishKey,
            subscribeKey: configuration.subscribeKey,
            userId: configuration.userId
        )
        
        // Note: Additional configuration options may vary by PubNub SDK version
        // Refer to PubNub SDK documentation for available properties

        pubnub = PubNub(configuration: pubNubConfig)

        logger.info("PubNub configured for daemon type: \(daemonType.rawValue)")
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

            logger.info("Successfully connected and subscribed to channels: \(channels)")

            // Start heartbeat
            startHeartbeat()

            // Send initial presence
            try await sendHeartbeat()

        } catch {
            updateConnectionStatus(.failed(error))
            logger.error("Failed to connect: \(error)")
            throw error
        }
    }

    public func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        pubnub?.unsubscribeAll()
        pubnub?.removeAllListeners()

        // Cancel all pending responses
        responsesLock.withLock {
            for (_, pending) in pendingResponses {
                pending.timeoutTask?.cancel()
            }
            pendingResponses.removeAll()
        }

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
        
        // Encode message to JSON string for PubNub
        let encoder = JSONEncoder()
        let messageData = try encoder.encode(message)
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            throw PubSubError.publishFailed(NSError(domain: "PubSubManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize message"]))
        }

        logger.debug("Publishing message of type \(message.messageType.rawValue) to channel \(targetChannel)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pubnub.publish(
                channel: targetChannel,
                message: messageString
            ) { result in
                switch result {
                case .success:
                    self.logger.debug("Message published successfully")
                    continuation.resume()
                case .failure(let error):
                    self.logger.error("Failed to publish message: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func publishAndWaitForResponse(
        command: CommandMessage,
        to channel: String? = nil,
        timeout: TimeInterval = 30.0
    ) async throws -> ResponseMessage {

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                let removed = responsesLock.withLock {
                    pendingResponses.removeValue(forKey: command.id)
                }
                
                if removed != nil {
                    logger.warning("Command \(command.id) timed out after \(timeout) seconds")
                    continuation.resume(throwing: PubSubError.timeout)
                }
            }
            
            let pendingResponse = PendingResponse(
                handler: { response in
                    timeoutTask.cancel()
                    continuation.resume(returning: response)
                },
                createdAt: Date(),
                timeoutTask: timeoutTask
            )
            
            responsesLock.withLock {
                pendingResponses[command.id] = pendingResponse
            }

            // Publish the command
            Task {
                do {
                    try await self.publish(message: command, to: channel)
                } catch {
                    responsesLock.withLock {
                        if let removed = pendingResponses.removeValue(forKey: command.id) {
                            removed.timeoutTask?.cancel()
                        }
                    }
                    
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
// Note: PubNub SDK event handling varies by version
// This is a placeholder for custom event handling implementation
extension PubSubManager {
    // Custom message handling would be implemented here
    // based on your specific PubNub SDK version and requirements
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
            return "Unsupported message type: \(type.rawValue)"
        case .publishFailed(let error):
            return "Failed to publish message: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Failed to subscribe: \(error.localizedDescription)"
        }
    }
}
