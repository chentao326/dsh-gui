#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK=""
for cand in MacOSX15.2.sdk MacOSX15.sdk MacOSX14.5.sdk MacOSX.sdk; do
  if [ -d "/Library/Developer/CommandLineTools/SDKs/$cand" ]; then SDK="/Library/Developer/CommandLineTools/SDKs/$cand"; break; fi
done
[ -n "$SDK" ] || { echo "ERROR: no SDK found under /Library/Developer/CommandLineTools/SDKs"; exit 1; }
mkdir -p build/modcache
echo "SDK: $SDK"

if [ "${1:-}" = "--test" ]; then
  chmod +x Tests/fake-dsh.sh
  swiftc -sdk "$SDK" -module-cache-path build/modcache \
    -Xcc -fmodules-cache-path="$PWD/build/modcache" \
    Sources/Core.swift Tests/main.swift -o build/tests 2>&1 | head -40
  ./build/tests
  swiftc -sdk "$SDK" -module-cache-path build/modcache \
    -Xcc -fmodules-cache-path="$PWD/build/modcache" -parse-as-library \
    Sources/Core.swift Tests/spawn.swift -o build/spawn-test 2>&1 | head -40
  ./build/spawn-test "$PWD/Tests/fake-dsh.sh"
  exit $?
fi

# ── 1. icon ───────────────────────────────────────────────────────
swiftc -sdk "$SDK" -module-cache-path build/modcache \
  -Xcc -fmodules-cache-path="$PWD/build/modcache" \
  scripts/svg2png.swift -o build/svg2png
./build/svg2png assets/AppIcon.svg build/icon-1024.png 1024
rm -rf build/AppIcon.iconset
mkdir -p build/AppIcon.iconset
sips -z 16 16 build/icon-1024.png --out build/AppIcon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 build/icon-1024.png --out build/AppIcon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 build/icon-1024.png --out build/AppIcon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 build/icon-1024.png --out build/AppIcon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 build/icon-1024.png --out build/AppIcon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 build/icon-1024.png --out build/AppIcon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 build/icon-1024.png --out build/AppIcon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 build/icon-1024.png --out build/AppIcon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 build/icon-1024.png --out build/AppIcon.iconset/icon_512x512.png >/dev/null
sips -z 1024 1024 build/icon-1024.png --out build/AppIcon.iconset/icon_512x512@2x.png >/dev/null
# iconutil 输出经临时文件+rename，需在不受文件沙箱拦截的临时目录生成
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
iconutil -c icns build/AppIcon.iconset -o "$ICON_TMP/AppIcon.icns"
cp "$ICON_TMP/AppIcon.icns" build/AppIcon.icns
echo "✅ icon: build/AppIcon.icns"

# ── 2. compile app ────────────────────────────────────────────────
swiftc -sdk "$SDK" -module-cache-path build/modcache \
  -Xcc -fmodules-cache-path="$PWD/build/modcache" -O -suppress-warnings \
  Sources/Core.swift Sources/App.swift Sources/main.swift -o build/DSH
echo "✅ binary: build/DSH"

# ── 3. assemble .app ─────────────────────────────────────────────
rm -rf build/DSH.app
mkdir -p build/DSH.app/Contents/MacOS build/DSH.app/Contents/Resources
cp build/DSH build/DSH.app/Contents/MacOS/
cp build/AppIcon.icns build/DSH.app/Contents/Resources/
cp Info.plist build/DSH.app/Contents/
echo "✅ bundle: build/DSH.app"

# ── 4. install to Desktop ────────────────────────────────────────
rm -rf "$HOME/Desktop/DSH.app"
if cp -R build/DSH.app "$HOME/Desktop/"; then
  echo "✅ installed: $HOME/Desktop/DSH.app"
else
  echo "⚠️ 无法写入桌面（权限受限），产物保留在 build/DSH.app，请手动复制"
fi
