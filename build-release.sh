#!/bin/bash
# Build Release Script for BetterCapture

set -e

echo "🚀 Building BetterCapture Release..."

# Configuration
APP_NAME="BetterCapture"
SCHEME="BetterCapture"
VERSION="1.0.0"
BUILD_DIR="build"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}

# Build archive
echo "📦 Building archive..."
xcodebuild archive \
    -project ${APP_NAME}.xcodeproj \
    -scheme ${SCHEME} \
    -configuration Release \
    -archivePath ${BUILD_DIR}/${APP_NAME}.xcarchive \
    -quiet

# Export app
echo "📤 Exporting app..."
xcodebuild -exportArchive \
    -archivePath ${BUILD_DIR}/${APP_NAME}.xcarchive \
    -exportPath ${BUILD_DIR}/${APP_NAME}-${VERSION} \
    -exportOptionsPlist exportOptions.plist \
    -quiet

# Create ZIP
echo "🗜️  Creating ZIP..."
cd ${BUILD_DIR}/${APP_NAME}-${VERSION}
zip -r ../${APP_NAME}-${VERSION}.zip ${APP_NAME}.app
cd ../..

# Calculate checksum
echo "🔐 Calculating checksum..."
cd ${BUILD_DIR}
shasum -a 256 ${APP_NAME}-${VERSION}.zip > ${APP_NAME}-${VERSION}.zip.sha256
cd ..

echo ""
echo "✅ Release build complete!"
echo ""
echo "📁 Output files:"
echo "   - ${BUILD_DIR}/${APP_NAME}-${VERSION}/${APP_NAME}.app"
echo "   - ${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
echo "   - ${BUILD_DIR}/${APP_NAME}-${VERSION}.zip.sha256"
echo ""
echo "📝 Next steps:"
echo "   1. Test the app thoroughly"
echo "   2. Create GitHub Release"
echo "   3. Upload ${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"
