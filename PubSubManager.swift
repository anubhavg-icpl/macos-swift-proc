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

        logger.debug("Publishing message of type \(message.messageType.rawValue) to channel \(targetChannel)")

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
                    self.logger.error("Failed to publish message: \(error)")
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
            logger.error("Subscription error: \(error)")
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

            logger.debug("Received message of type \(decodedMessage.messageType.rawValue) from \(decodedMessage.source.rawValue)")

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
            logger.error("Failed to process received message: \(error)")
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
            return "Unsupported message type: \(type.rawValue)"
        case .publishFailed(let error):
            return "Failed to publish message: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Failed to subscribe: \(error.localizedDescription)"
        }
    }
}
