//
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
        self.osLogger = OSLog(subsystem: "com.dualdaemon.\(daemonType.rawValue)", category: "general")

        // Setup Swift Logger
        var logger = Logger(label: "dualdaemon.\(daemonType.rawValue)")
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
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Use os_log as fallback since file logging isn't available
            os_log("CRITICAL: Failed to create log directory at %{public}@: %{public}@", 
                   log: osLogger, type: .fault, logPath, error.localizedDescription)
            return
        }

        // Create log file path for this daemon
        let logFile = logDirectory.appendingPathComponent("\(daemonType.rawValue).log")

        // Setup log rotation if file is too large
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFile.path)
            if let fileSize = attributes[.size] as? Int,
               fileSize > configuration.maxLogFileSize {
                do {
                    try rotateLogFile(logFile)
                } catch {
                    os_log("ERROR: Failed to rotate log file: %{public}@", 
                           log: osLogger, type: .error, error.localizedDescription)
                }
            }
        } catch CocoaError.fileReadNoSuchFile {
            // File doesn't exist yet, this is fine
        } catch {
            os_log("WARNING: Failed to check log file size: %{public}@", 
                   log: osLogger, type: .default, error.localizedDescription)
        }
    }

    private func rotateLogFile(_ logFile: URL) throws {
        // Delete the oldest rotation if it exists
        let oldestRotation = logFile.appendingPathExtension("\(configuration.logRotationCount)")
        if FileManager.default.fileExists(atPath: oldestRotation.path) {
            try FileManager.default.removeItem(at: oldestRotation)
        }
        
        // Rotate existing files
        for i in (1..<configuration.logRotationCount).reversed() {
            let oldFile = logFile.appendingPathExtension("\(i)")
            let newFile = logFile.appendingPathExtension("\(i + 1)")

            if FileManager.default.fileExists(atPath: oldFile.path) {
                try FileManager.default.moveItem(at: oldFile, to: newFile)
            }
        }

        // Move current log to .1
        if FileManager.default.fileExists(atPath: logFile.path) {
            let firstRotation = logFile.appendingPathExtension("1")
            try FileManager.default.moveItem(at: logFile, to: firstRotation)
        }
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
        let formattedMessage = "[\(daemonType.rawValue)] \(filename):\(line) \(function) - \(message)"

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
        let logFile = logDirectory.appendingPathComponent("\(daemonType.rawValue).log")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)\n"

        guard let data = logLine.data(using: .utf8) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let fileHandle = try FileHandle(forWritingTo: logFile)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
            } else {
                try data.write(to: logFile, options: .atomic)
            }
        } catch {
            // Last resort: log to os_log
            os_log("CRITICAL: Failed to write to log file: %{public}@", 
                   log: osLogger, type: .fault, error.localizedDescription)
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
