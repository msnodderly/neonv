#!/bin/bash
set -e

# Configuration
PROJECT_DIR="NeoNV"
PROJECT_NAME="NeoNV"
SCHEME="NeoNV"
DERIVED_DATA_PATH=".build"

# Ensure we're in the project root
cd "$(dirname "$0")"

echo "Building $SCHEME..."
xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
           -scheme "$SCHEME" \
           -configuration Debug \
           -derivedDataPath "$DERIVED_DATA_PATH" \
           -quiet

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/$SCHEME.app"

if [ -d "$APP_PATH" ]; then
    echo "Launching $SCHEME..."
    open "$APP_PATH"
else
    echo "Error: App not found at $APP_PATH"
    exit 1
fi
