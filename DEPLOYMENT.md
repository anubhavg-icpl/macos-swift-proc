# Production Deployment Guide

## Pre-Deployment Checklist

### Infrastructure Requirements

- [ ] macOS 12.0+ servers provisioned
- [ ] Network connectivity verified
- [ ] PubNub account created and configured
- [ ] Monitoring system ready
- [ ] Backup procedures documented

### Security Requirements

- [ ] Encryption keys generated (32+ characters, cryptographically secure)
- [ ] PubNub credentials obtained (publish + subscribe keys)
- [ ] Code signing certificate acquired
- [ ] Notarization credentials configured
- [ ] Security policy reviewed and approved

### Build Requirements

- [ ] Xcode Command Line Tools installed
- [ ] Swift 5.9+ verified
- [ ] Build script tested
- [ ] Universal binaries created (arm64 + x86_64)

## Step-by-Step Deployment

### 1. Prepare Credentials

```bash
# Generate strong encryption key
ENCRYPTION_KEY=$(openssl rand -base64 32)
echo "Generated encryption key: $ENCRYPTION_KEY"

# Store securely (use secrets management system in production)
# Examples: macOS Keychain, HashiCorp Vault, AWS Secrets Manager
```

### 2. Build for Production

```bash
cd /path/to/macos-swift-proc

# Clean environment
swift package clean
rm -rf .build/

# Build release binaries
./Scripts/build.sh release

# Verify binaries
file .build/apple/Products/Release/user-daemon
file .build/apple/Products/Release/system-daemon
```

### 3. Code Signing (Required for Production)

```bash
# Sign binaries
codesign --sign "Developer ID Application: Your Name (TEAMID)" \
         --timestamp \
         --options runtime \
         .build/apple/Products/Release/user-daemon

codesign --sign "Developer ID Application: Your Name (TEAMID)" \
         --timestamp \
         --options runtime \
         .build/apple/Products/Release/system-daemon

# Verify signatures
codesign --verify --verbose .build/apple/Products/Release/user-daemon
codesign --verify --verbose .build/apple/Products/Release/system-daemon

# Check notarization requirements
spctl --assess --verbose .build/apple/Products/Release/user-daemon
```

### 4. Configure Launch Plists

```bash
# Copy templates
sudo cp Resources/LaunchDaemons/com.dualdaemon.system.plist /tmp/
sudo cp Resources/LaunchAgents/com.dualdaemon.user.plist /tmp/

# Edit with real credentials (NEVER commit these)
sudo nano /tmp/com.dualdaemon.system.plist
sudo nano /tmp/com.dualdaemon.user.plist

# Verify format
plutil -lint /tmp/com.dualdaemon.system.plist
plutil -lint /tmp/com.dualdaemon.user.plist
```

### 5. Install on Target System

```bash
# Install daemons
sudo ./Scripts/install.sh

# Install configured plists
sudo cp /tmp/com.dualdaemon.system.plist /Library/LaunchDaemons/
sudo cp /tmp/com.dualdaemon.user.plist /Library/LaunchAgents/

# Set correct permissions
sudo chmod 644 /Library/LaunchDaemons/com.dualdaemon.system.plist
sudo chmod 644 /Library/LaunchAgents/com.dualdaemon.user.plist
sudo chown root:wheel /Library/LaunchDaemons/com.dualdaemon.system.plist
sudo chown root:wheel /Library/LaunchAgents/com.dualdaemon.user.plist

# Secure log directory
sudo chmod 755 /var/log/dualdaemon
sudo mkdir -p /var/log/dualdaemon
```

### 6. Pre-Flight Testing

```bash
# Test system daemon manually first
sudo /usr/local/sbin/system-daemon &
sleep 5
sudo pkill system-daemon

# Check logs for errors
cat /var/log/dualdaemon/system-daemon.stderr

# Test user daemon manually
/usr/local/bin/user-daemon &
sleep 5
pkill user-daemon

# Check logs
cat /var/log/dualdaemon/user-daemon.stderr
```

### 7. Load Daemons

```bash
# Load system daemon
sudo launchctl load /Library/LaunchDaemons/com.dualdaemon.system.plist

# Verify it's running
sudo launchctl list | grep dualdaemon

# Load user daemon
launchctl load /Library/LaunchAgents/com.dualdaemon.user.plist

# Verify it's running
launchctl list | grep dualdaemon
```

### 8. Verify Operation

```bash
# Check process status
ps aux | grep daemon

# Check logs
tail -f /var/log/dualdaemon/system-daemon.log
tail -f /var/log/dualdaemon/user-daemon.log

# Check system logs
log show --predicate 'subsystem == "com.dualdaemon"' --last 5m

# Verify PubNub connectivity
# Should see heartbeat messages in logs
```

## Monitoring Setup

### Log Monitoring

```bash
# Set up log forwarding to central logging system
# Example with syslog:
sudo vim /etc/syslog.conf
# Add: local0.* @logserver.example.com:514

# Restart syslog
sudo launchctl unload /System/Library/LaunchDaemons/com.apple.syslogd.plist
sudo launchctl load /System/Library/LaunchDaemons/com.apple.syslogd.plist
```

### Health Checks

Create a health check script:

```bash
#!/bin/bash
# /usr/local/bin/dualdaemon-health-check

USER_DAEMON_PID=$(launchctl list | grep dualdaemon.user | awk '{print $1}')
SYSTEM_DAEMON_PID=$(sudo launchctl list | grep dualdaemon.system | awk '{print $1}')

if [ "$USER_DAEMON_PID" = "-" ] || [ "$SYSTEM_DAEMON_PID" = "-" ]; then
    echo "CRITICAL: Daemon not running"
    exit 2
fi

# Check log for recent activity (within last 5 minutes)
LAST_LOG=$(tail -1 /var/log/dualdaemon/system-daemon.log | grep -o '\[.*\]' | head -1)
# Add timestamp comparison logic here

echo "OK: Daemons running"
exit 0
```

### Alerting

Configure alerts for:
- Daemon crash/restart
- Failed heartbeats
- Connection errors
- High memory usage
- Log errors/criticals

## Rollback Procedure

If deployment fails:

```bash
# Unload daemons
sudo launchctl unload /Library/LaunchDaemons/com.dualdaemon.system.plist
launchctl unload /Library/LaunchAgents/com.dualdaemon.user.plist

# Remove new versions
sudo mv /usr/local/sbin/system-daemon /usr/local/sbin/system-daemon.new
sudo mv /usr/local/bin/user-daemon /usr/local/bin/user-daemon.new

# Restore previous versions
sudo cp /backup/system-daemon /usr/local/sbin/
sudo cp /backup/user-daemon /usr/local/bin/

# Reload daemons
sudo launchctl load /Library/LaunchDaemons/com.dualdaemon.system.plist
launchctl load /Library/LaunchAgents/com.dualdaemon.user.plist
```

## Troubleshooting

### Daemon Won't Start

1. Check credentials in plist
2. Verify binary permissions (755)
3. Check stderr logs
4. Test binary manually
5. Verify network connectivity

### High Memory Usage

1. Check for message queue buildup
2. Review log rotation settings
3. Check pending responses count
4. Monitor for leaks with Instruments

### Connection Failures

1. Verify PubNub credentials
2. Check network connectivity
3. Review firewall rules
4. Test PubNub API directly

## Performance Tuning

### Log Rotation

Adjust in plist or configuration:
```xml
<key>DAEMON_MAX_LOG_SIZE</key>
<string>10485760</string>
<key>DAEMON_LOG_ROTATION_COUNT</key>
<string>5</string>
```

### Heartbeat Interval

Adjust based on requirements:
- More frequent: Better monitoring, more network traffic
- Less frequent: Lower overhead, delayed failure detection

### Message Timeout

Default 30s, adjust based on network latency and requirements.

## Security Hardening

### Network Security

- Use PubNub Access Manager for channel-level security
- Enable TLS 1.3 only
- Restrict source IPs if possible
- Use VPN for sensitive deployments

### File Permissions

```bash
# Lock down binaries
sudo chmod 755 /usr/local/bin/user-daemon
sudo chmod 755 /usr/local/sbin/system-daemon
sudo chown root:wheel /usr/local/bin/user-daemon
sudo chown root:wheel /usr/local/sbin/system-daemon

# Protect logs
sudo chmod 755 /var/log/dualdaemon
sudo chown root:wheel /var/log/dualdaemon
```

### Credential Rotation

Schedule regular rotation of:
- PubNub keys (every 90 days)
- Encryption keys (every 180 days)
- Update all systems during maintenance window

## Backup and Recovery

### Configuration Backup

```bash
# Backup configuration
sudo tar -czf dualdaemon-config-$(date +%Y%m%d).tar.gz \
    /Library/LaunchDaemons/com.dualdaemon.system.plist \
    /Library/LaunchAgents/com.dualdaemon.user.plist \
    /etc/dualdaemon/

# Store securely offsite
```

### Log Backup

```bash
# Backup logs
sudo tar -czf dualdaemon-logs-$(date +%Y%m%d).tar.gz \
    /var/log/dualdaemon/

# Archive to long-term storage
```

## Compliance

### Audit Logging

- All message exchanges logged
- Privileged operations logged
- Failed authentication attempts logged
- Configuration changes logged

### Data Retention

- Logs retained for 90 days by default
- Compliance requirements may dictate longer retention
- Configure log forwarding for long-term storage

## Support Contacts

- **Emergency**: [Emergency contact]
- **On-Call**: [On-call rotation]
- **PubNub Support**: support@pubnub.com
- **Security Incidents**: security@yourcompany.com

---

**Remember**: Production deployment is not complete until monitoring, alerting, and backup procedures are fully operational.
