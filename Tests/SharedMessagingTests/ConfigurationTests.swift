import XCTest
@testable import SharedMessaging

final class ConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        // Note: This test will fail if environment variables aren't set
        // In production testing, mock the environment
        let config = AppConfiguration.default
        
        XCTAssertNotNil(config.pubSubConfig)
        XCTAssertNotNil(config.loggingConfig)
        XCTAssertNotNil(config.securityConfig)
    }
    
    func testConfigurationSerialization() throws {
        let config = AppConfiguration(
            pubSubConfig: PubSubConfiguration(
                publishKey: "test_pub",
                subscribeKey: "test_sub",
                userId: "test_user",
                channels: .default
            ),
            loggingConfig: LoggingConfiguration(
                logLevel: .debug,
                logToFile: true,
                logFilePath: "/tmp/test"
            ),
            securityConfig: SecurityConfiguration(
                enableEncryption: false,
                encryptionKey: nil,
                allowedSources: nil,
                requireSignatures: false
            )
        )
        
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)
        
        XCTAssertEqual(config.pubSubConfig.publishKey, decoded.pubSubConfig.publishKey)
        XCTAssertEqual(config.loggingConfig.logLevel, decoded.loggingConfig.logLevel)
        XCTAssertEqual(config.securityConfig.enableEncryption, decoded.securityConfig.enableEncryption)
    }
    
    func testLogLevelConversion() {
        XCTAssertEqual(LogLevel.trace.swiftLogLevel, .trace)
        XCTAssertEqual(LogLevel.debug.swiftLogLevel, .debug)
        XCTAssertEqual(LogLevel.info.swiftLogLevel, .info)
        XCTAssertEqual(LogLevel.error.swiftLogLevel, .error)
        XCTAssertEqual(LogLevel.critical.swiftLogLevel, .critical)
    }
}
