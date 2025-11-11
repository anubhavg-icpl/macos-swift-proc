//
//  main.swift
//  UserDaemon
//
//  User-level daemon for dual daemon system
//

import Foundation
import Logging
import PubNubSDK
import SharedMessaging

@main
struct UserDaemon {
    static func main() async {
        // Initialize logger
        let configuration = ConfigurationManager.shared.configuration
        let logger = DaemonLogger(daemonType: .user, configuration: configuration.loggingConfig)
        
        logger.info("UserDaemon starting...")
        logger.info("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        logger.info("User: \(NSUserName())")
        
        // Initialize PubSub manager
        let pubSubLogger = Logger(label: "dualdaemon.user.pubsub")
        let pubSubManager = await PubSubManager(
            configuration: configuration.pubSubConfig,
            daemonType: .user,
            logger: pubSubLogger
        )
        
        // Set up signal handlers for graceful shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler {
            logger.info("Received SIGTERM, initiating graceful shutdown...")
            Task {
                await pubSubManager.disconnect()
                exit(0)
            }
        }
        signalSource.resume()
        signal(SIGTERM, SIG_IGN)
        
        // Connect to PubNub
        do {
            try await pubSubManager.connect()
            logger.info("UserDaemon successfully connected to messaging system")
            
            // Send initial status
            let statusMessage = SystemStatusMessage(
                source: .user,
                status: .healthy,
                details: ["version": "1.0.0", "pid": "\(ProcessInfo.processInfo.processIdentifier)"]
            )
            try await pubSubManager.publish(message: statusMessage)
            
        } catch {
            logger.critical("Failed to connect to messaging system: \(error)")
            exit(1)
        }
        
        // Keep daemon running
        logger.info("UserDaemon is now running. Press Ctrl+C to stop.")
        RunLoop.main.run()
    }
}
