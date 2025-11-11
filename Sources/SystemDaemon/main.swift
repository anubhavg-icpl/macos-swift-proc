//
//  main.swift
//  SystemDaemon
//
//  System-level daemon for dual daemon system (requires root privileges)
//

import Foundation
import Logging
import PubNubSDK
import SharedMessaging

@main
struct SystemDaemon {
    static func main() async {
        // Verify running as root
        guard getuid() == 0 else {
            print("FATAL: SystemDaemon must run as root")
            exit(1)
        }
        
        // Initialize logger
        let configuration = ConfigurationManager.shared.configuration
        let logger = DaemonLogger(daemonType: .system, configuration: configuration.loggingConfig)
        
        logger.info("SystemDaemon starting...")
        logger.info("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        logger.info("User: root (UID: \(getuid()))")
        
        // Initialize PubSub manager
        let pubSubLogger = Logger(label: "dualdaemon.system.pubsub")
        let pubSubManager = await PubSubManager(
            configuration: configuration.pubSubConfig,
            daemonType: .system,
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
            logger.info("SystemDaemon successfully connected to messaging system")
            
            // Send initial status
            let statusMessage = SystemStatusMessage(
                source: .system,
                status: .healthy,
                details: ["version": "1.0.0", "pid": "\(ProcessInfo.processInfo.processIdentifier)"]
            )
            try await pubSubManager.publish(message: statusMessage)
            
        } catch {
            logger.critical("Failed to connect to messaging system: \(error)")
            exit(1)
        }
        
        // Keep daemon running
        logger.info("SystemDaemon is now running. Use launchctl to stop.")
        RunLoop.main.run()
    }
}
