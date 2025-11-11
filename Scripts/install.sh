#!/bin/bash
# Installation script for DualDaemonApp
# Must be run with sudo

set -e

if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==================================="
echo "Installing DualDaemonApp"
echo "==================================="

# Check if binaries exist
USER_DAEMON="$PROJECT_ROOT/.build/apple/Products/Release/user-daemon"
SYSTEM_DAEMON="$PROJECT_ROOT/.build/apple/Products/Release/system-daemon"

if [ ! -f "$USER_DAEMON" ]; then
    USER_DAEMON="$PROJECT_ROOT/.build/release/user-daemon"
fi

if [ ! -f "$SYSTEM_DAEMON" ]; then
    SYSTEM_DAEMON="$PROJECT_ROOT/.build/release/system-daemon"
fi

if [ ! -f "$USER_DAEMON" ] || [ ! -f "$SYSTEM_DAEMON" ]; then
    echo "ERROR: Binaries not found. Run ./Scripts/build.sh first."
    exit 1
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p /var/log/dualdaemon
mkdir -p /etc/dualdaemon
mkdir -p /usr/local/bin
mkdir -p /usr/local/sbin

# Install binaries
echo "Installing binaries..."
cp "$USER_DAEMON" /usr/local/bin/user-daemon
cp "$SYSTEM_DAEMON" /usr/local/sbin/system-daemon

chmod 755 /usr/local/bin/user-daemon
chmod 755 /usr/local/sbin/system-daemon

# Install launch plists
echo "Installing launch configuration..."

# System daemon (LaunchDaemon - runs as root)
cp "$PROJECT_ROOT/Resources/LaunchDaemons/com.dualdaemon.system.plist" /Library/LaunchDaemons/
chmod 644 /Library/LaunchDaemons/com.dualdaemon.system.plist
chown root:wheel /Library/LaunchDaemons/com.dualdaemon.system.plist

# User daemon (LaunchAgent - runs as user)
LAUNCH_AGENTS_DIR="/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$PROJECT_ROOT/Resources/LaunchAgents/com.dualdaemon.user.plist" "$LAUNCH_AGENTS_DIR/"
chmod 644 "$LAUNCH_AGENTS_DIR/com.dualdaemon.user.plist"
chown root:wheel "$LAUNCH_AGENTS_DIR/com.dualdaemon.user.plist"

# Set permissions
echo "Setting permissions..."
chmod 755 /var/log/dualdaemon
chmod 755 /etc/dualdaemon

echo ""
echo "==================================="
echo "Installation complete!"
echo "==================================="
echo ""
echo "IMPORTANT: Before starting the daemons, you MUST:"
echo "1. Edit /Library/LaunchDaemons/com.dualdaemon.system.plist"
echo "2. Edit /Library/LaunchAgents/com.dualdaemon.user.plist"
echo "3. Set your PubNub credentials and encryption key"
echo ""
echo "To load the daemons:"
echo "  System daemon: sudo launchctl load /Library/LaunchDaemons/com.dualdaemon.system.plist"
echo "  User daemon:   launchctl load /Library/LaunchAgents/com.dualdaemon.user.plist"
echo ""
echo "To unload the daemons:"
echo "  System daemon: sudo launchctl unload /Library/LaunchDaemons/com.dualdaemon.system.plist"
echo "  User daemon:   launchctl unload /Library/LaunchAgents/com.dualdaemon.user.plist"
echo ""
