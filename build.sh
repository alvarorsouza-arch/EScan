#!/bin/zsh
# build.sh - compila o binario, o pdfmerge e monta o Escanear.app
set -e
cd "$(dirname "$0")"

print "==> scanui (GUI)"
/usr/bin/swiftc -O -o scanui scanview.swift main.swift

print "==> pdfmerge (junta PDFs)"
/usr/bin/swiftc -O -o pdfmerge pdfmerge.swift

print "==> Escanear.app"
APP="Escanear.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp scanui "$APP/Contents/MacOS/Escanear"
cp scan pdfmerge "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Escanear</string>
    <key>CFBundleDisplayName</key><string>Escanear</string>
    <key>CFBundleExecutable</key><string>Escanear</string>
    <key>CFBundleIdentifier</key><string>escan.airscan</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

print ""
print "pronto: Escanear.app, scanui, pdfmerge"
print "para instalar em /Applications:  sudo cp -R Escanear.app /Applications/"
