#!/bin/bash
# Build script for DualDaemonApp
# Usage: ./build.sh [debug|release]

set -e  # Exit on error

BUILD_CONFIG="${1:-release}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==================================="
echo "Building DualDaemonApp"
echo "Configuration: $BUILD_CONFIG"
echo "==================================="

cd "$PROJECT_ROOT"

# Clean previous build
echo "Cleaning previous build..."
swift package clean

# Build the package
echo "Building package..."
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release --arch arm64 --arch x86_64
else
    swift build -c debug
fi

echo ""
echo "Build completed successfully!"
echo ""
echo "Binaries location:"
if [ "$BUILD_CONFIG" = "release" ]; then
    echo "  User Daemon: .build/apple/Products/Release/user-daemon"
    echo "  System Daemon: .build/apple/Products/Release/system-daemon"
else
    echo "  User Daemon: .build/debug/user-daemon"
    echo "  System Daemon: .build/debug/system-daemon"
fi
