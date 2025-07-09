# DualDaemonApp

A production-grade macOS application demonstrating dual-daemon architecture with real-time inter-process communication.

## Overview

DualDaemonApp implements a robust system consisting of two cooperating daemons - a user-level daemon (Launch Agent) and a system-level daemon (Launch Daemon) - that communicate using a publish-subscribe messaging pattern. This architecture enables seamless coordination between user and system contexts while maintaining proper privilege separation.

## Features

### Core Architecture
- **Dual Daemon System**: User daemon and system daemon working in tandem
- **Real-time Communication**: PubNub-based messaging for instant IPC
- **Health Monitoring**: Automatic heartbeat and status tracking
- **Command Execution**: Secure command/response pattern with correlation

### Production Features
- **Connection Resilience**: Automatic reconnection and error recovery
- **Comprehensive Logging**: Multi-level logging with automatic rotation
- **System Metrics**: CPU and memory usage monitoring
- **Message Priorities**: Support for critical, high, normal, and low priority messages
- **Configuration Management**: Environment-based configuration with sensible defaults

## Requirements

- macOS 12.0 or later
- Swift 5.9+
- PubNub account (for messaging infrastructure)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/anubhavg-icpl/macos-swift-proc.git
cd macos-swift-proc
```

2. Build the project:
```bash
swift build -c release
```

3. Configure PubNub credentials:
```bash
export PUBNUB_PUBLISH_KEY="your-publish-key"
export PUBNUB_SUBSCRIBE_KEY="your-subscribe-key"
```

4. Install the daemons (requires admin privileges):
```bash
sudo ./install.sh
```

## Project Structure

```
macos-swift-proc/
├── Sources/
│   ├── DualDaemonMessaging/      # Shared messaging library
│   │   ├── PubSubManager.swift   # Core messaging infrastructure
│   │   ├── MessageTypes.swift    # Message protocol definitions
│   │   ├── Configuration.swift   # Configuration management
│   │   └── Logger.swift          # Logging infrastructure
│   ├── UserDaemon/               # User-level daemon
│   │   └── main.swift
│   └── SystemDaemon/             # System-level daemon
│       └── main.swift
├── Package.swift                 # Swift package manifest
└── README.md
```

## Configuration

The application can be configured through:

1. **Environment Variables**:
   - `PUBNUB_PUBLISH_KEY`
   - `PUBNUB_SUBSCRIBE_KEY`
   - `DAEMON_LOG_LEVEL`

2. **Configuration File**: `/etc/dualdaemon/config.json`
```json
{
  "pubnub": {
    "publishKey": "your-key",
    "subscribeKey": "your-key"
  },
  "logging": {
    "level": "info",
    "maxFileSize": 10485760
  }
}
```

## Usage

Once installed, the daemons start automatically and begin exchanging heartbeat messages. You can interact with them through:

1. **System Logs**: View daemon activity
```bash
log show --predicate 'subsystem == "com.dualdaemon"' --last 1h
```

2. **Command Line Tools**: Send commands to daemons (if implemented)
```bash
dualdaemon-cli send-command --target system --command restart-service
```

## Architecture Details

### Message Types
- **Heartbeat**: System health and resource usage
- **SystemStatus**: Daemon operational status
- **Command**: Execute operations with parameters
- **Response**: Command execution results

### Communication Flow
1. Daemons establish PubNub connections on startup
2. Heartbeats are exchanged every 30 seconds
3. Commands can be sent with unique correlation IDs
4. Responses are matched to requests via correlation

## Development

### Building
```bash
swift build
```

### Testing
```bash
swift test
```

### Running Locally
```bash
# User daemon
swift run UserDaemon

# System daemon (requires sudo)
sudo swift run SystemDaemon
```

## Security Considerations

- Message encryption support via PubNub
- Configurable allowed message sources
- Privilege separation between user and system contexts
- No sensitive data in logs

## Use Cases

- System monitoring and management tools
- Security applications requiring dual-context operation
- Background synchronization services
- Privileged operations with user interaction

## License

This project is available under the MIT License. See LICENSE file for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.
