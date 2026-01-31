#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$PROJECT_ROOT/NeoNV"
PROJECT_NAME="NeoNV"
SCHEME="NeoNV"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build a release .app, DMG, and ZIP for NeoNV."
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION   Set version (default: git describe or 'dev')"
    echo "  -o, --output DIR        Output directory (default: ./release)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Build with version from git describe"
    echo "  $0 -v 1.0.0             # Build with explicit version"
    echo "  $0 -o ./dist            # Build to custom output directory"
}

get_version() {
    if git describe --tags --exact-match 2>/dev/null; then
        return
    fi
    if git describe --tags 2>/dev/null; then
        return
    fi
    echo "dev-$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}

VERSION=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

VERSION="${VERSION:-$(get_version)}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/release}"

echo "=== NeoNV Release Build ==="
echo "Version: $VERSION"
echo "Output:  $OUTPUT_DIR"
echo ""

BUILD_DIR="$PROJECT_ROOT/.build-release"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_NAME="$SCHEME.app"
ARTIFACT_BASE="NeoNV-${VERSION}-macos-universal"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo "==> Archiving (Universal Binary: arm64 + x86_64)..."
xcodebuild archive \
    -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    -quiet

echo "==> Exporting .app from archive..."
cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>signingCertificate</key>
    <string>-</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet 2>/dev/null || {
    echo "    (export failed, falling back to direct copy from archive)"
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$EXPORT_PATH/"
}

APP_PATH="$EXPORT_PATH/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: .app not found at $APP_PATH"
    exit 1
fi

echo "==> Verifying universal binary..."
ARCH_INFO=$(lipo -info "$APP_PATH/Contents/MacOS/$SCHEME" 2>/dev/null || echo "unknown")
echo "    $ARCH_INFO"

echo "==> Creating ZIP..."
ZIP_PATH="$OUTPUT_DIR/${ARTIFACT_BASE}.zip"
(cd "$EXPORT_PATH" && ditto -c -k --keepParent "$APP_NAME" "$ZIP_PATH")
echo "    Created: $ZIP_PATH"

echo "==> Creating DMG..."
DMG_PATH="$OUTPUT_DIR/${ARTIFACT_BASE}.dmg"
DMG_TEMP="$BUILD_DIR/dmg-staging"

mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create \
    -volname "NeoNV $VERSION" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    -quiet

echo "    Created: $DMG_PATH"

rm -rf "$BUILD_DIR"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Artifacts:"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
echo ""

cat << EOF
# For CI consumption (GitHub Actions):
echo "dmg_path=$DMG_PATH" >> \$GITHUB_OUTPUT
echo "zip_path=$ZIP_PATH" >> \$GITHUB_OUTPUT
echo "version=$VERSION" >> \$GITHUB_OUTPUT
EOF
