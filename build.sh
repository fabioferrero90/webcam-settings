#!/bin/zsh
# Builds "Webcam Settings.app" into build/
set -e
cd "$(dirname "$0")"
APP="build/Webcam Settings.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj build/AppIcon.iconset
swift make-icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp -R it.lproj fr.lproj de.lproj es.lproj "$APP/Contents/Resources/"
clang -c uvc.c -o build/obj/uvc.o
swiftc -O -parse-as-library -import-objc-header uvc.h main.swift build/obj/uvc.o \
  -framework IOKit -framework AVFoundation -o "$APP/Contents/MacOS/WebcamSettings"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Webcam Settings</string>
  <key>CFBundleDisplayName</key><string>Webcam Settings</string>
  <key>CFBundleIdentifier</key><string>io.github.fabioferrero90.webcam-settings</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>WebcamSettings</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string><string>fr</string><string>de</string><string>es</string></array>
  <key>LSHasLocalizedDisplayName</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Used to show a live preview while you adjust the webcam.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built: $APP"
