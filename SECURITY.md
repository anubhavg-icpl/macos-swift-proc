# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Considerations

### Credentials Management

**CRITICAL**: Never commit credentials to version control.

- PubNub keys must be set via environment variables
- Encryption keys must be provided securely
- Launch plist files contain placeholder values that MUST be replaced

### Environment Variables

Required environment variables:
- `PUBNUB_PUBLISH_KEY` - PubNub publish key (required)
- `PUBNUB_SUBSCRIBE_KEY` - PubNub subscribe key (required)
- `DUALDAEMON_ENCRYPTION_KEY` - Encryption key (required if encryption enabled)
- `PUBNUB_USER_ID` - User identifier (optional, auto-generated if not provided)

### File Permissions

- Launch Daemon plists: 644, owned by root:wheel
- Launch Agent plists: 644, owned by root:wheel
- Binaries: 755
- Log directory: 755

### Encryption

- Message encryption is enabled by default
- Encryption key must be at least 32 characters
- Use strong, randomly generated keys
- Rotate keys regularly

### Network Security

- All communication goes through PubNub's secure infrastructure
- TLS encryption in transit
- Consider enabling PubNub Access Manager for additional security

## Reporting a Vulnerability

To report a security vulnerability:

1. **Do NOT** open a public GitHub issue
2. Email security concerns to: [your-email]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will respond within 48 hours and provide a timeline for a fix.

## Security Best Practices

### Production Deployment

1. **Use Secrets Management**: Store credentials in system keychain or secrets manager
2. **Enable Encryption**: Always enable message encryption in production
3. **Restrict Access**: Use PubNub Access Manager to restrict channel access
4. **Monitor Logs**: Regularly review daemon logs for suspicious activity
5. **Update Dependencies**: Keep Swift packages updated for security patches

### Code Signing

For production deployment:
- Sign binaries with valid Apple Developer certificate
- Enable hardened runtime
- Notarize applications
- Use entitlements appropriately

### Privilege Separation

- User daemon runs with user privileges
- System daemon runs with root privileges only when necessary
- Minimize privileged operations
- Validate all inter-daemon messages

## Known Security Considerations

1. **Root Execution**: System daemon requires root. Ensure minimal privileged operations.
2. **Message Validation**: Implement message signature verification for critical operations.
3. **Log File Security**: Log files may contain sensitive information. Secure appropriately.
4. **Network Dependency**: System relies on network connectivity to PubNub.

## Security Checklist for Deployment

- [ ] All credentials set via environment variables (not hardcoded)
- [ ] Encryption enabled with strong key
- [ ] Binaries code-signed and notarized
- [ ] Launch plists have correct permissions
- [ ] Logs secured with appropriate permissions
- [ ] PubNub Access Manager configured (if using)
- [ ] Regular security updates scheduled
- [ ] Monitoring and alerting configured
- [ ] Incident response plan documented
