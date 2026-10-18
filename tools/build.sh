#!/usr/bin/env bash
# Builds distributable packages into dist/.
#
# Usage: tools/build.sh <target>...
#   web-js         Web, Dart compiled to JavaScript (plus CanvasKit). Works in every browser.
#   web-skwasm     Web, Dart compiled to WebAssembly, skwasm renderer (falls back to JS).
#   macos-app      Penumbra.app                         (run on macOS)
#   macos-dmg      Penumbra-<version>.dmg               (run on macOS)
#   ios-app        Penumbra.app, unsigned, + .ipa       (run on macOS)
#   linux-appimage Penumbra-<version>-<arch>.AppImage   (run on Linux)
#   android-xapk   Penumbra-<version>.xapk              (needs the Android SDK)
#   windows-msi    Penumbra-<version>-x64.msi           (run on Windows in Git Bash; needs the WiX 4 CLI:
#                                                        dotnet tool install --global wix --version "4.*")
#
# Each target creates the platform folder first if it is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$PWD/dist"
mkdir -p "$OUT"
VERSION_FULL="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
VERSION="${VERSION_FULL%%+*}"
BUILD="${VERSION_FULL##*+}"
[ "$BUILD" = "$VERSION_FULL" ] && BUILD=1

ensure() { [ -d "$1" ] || bash tools/setup_platforms.sh "$1"; }
need_os() {
  if [ "$(uname -s)" != "$1" ]; then
    echo "error: $2 can only be built on $1." >&2
    exit 1
  fi
}

web_js() {
  ensure web
  # No --wasm: Dart is compiled to JavaScript. Rendering still uses CanvasKit,
  # which ships its own small .wasm; the app needs it for its fragment shaders.
  flutter build web --release --output "$OUT/web-js"
}

web_skwasm() {
  ensure web
  # --wasm compiles Dart to WebAssembly and renders with skwasm. The output also
  # contains the JS build, which browsers without WasmGC fall back to.
  flutter build web --release --wasm --output "$OUT/web-skwasm"
  # Multi-threaded skwasm needs cross-origin isolation. Netlify and Cloudflare
  # Pages read this file; other hosts need the same two headers set.
  cat > "$OUT/web-skwasm/_headers" <<'HDR'
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: credentialless
HDR
}

macos_app() {
  need_os Darwin "macos-app"
  ensure macos
  flutter build macos --release
  local app
  app="$(ls -d build/macos/Build/Products/Release/*.app | head -1)"
  rm -rf "$OUT/Penumbra.app"
  ditto "$app" "$OUT/Penumbra.app"
}

macos_dmg() {
  need_os Darwin "macos-dmg"
  [ -d "$OUT/Penumbra.app" ] || macos_app
  local stage
  stage="$(mktemp -d)"
  ditto "$OUT/Penumbra.app" "$stage/Penumbra.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$OUT/Penumbra-$VERSION.dmg"
  hdiutil create -volname "Penumbra" -srcfolder "$stage" -ov -format UDZO "$OUT/Penumbra-$VERSION.dmg"
  rm -rf "$stage"
}

ios_app() {
  need_os Darwin "ios-app"
  ensure ios
  flutter build ios --release --no-codesign
  rm -rf "$OUT/ios"
  mkdir -p "$OUT/ios/Payload"
  ditto build/ios/iphoneos/Runner.app "$OUT/ios/Penumbra.app"
  ditto build/ios/iphoneos/Runner.app "$OUT/ios/Payload/Penumbra.app"
  # An .app is a folder, so also ship it zipped, and as an unsigned .ipa for
  # tools that re-sign (AltStore, Sideloadly, ...).
  (cd "$OUT/ios" && zip -qr "../Penumbra-ios-$VERSION.app.zip" Penumbra.app \
    && zip -qr "../Penumbra-ios-$VERSION-unsigned.ipa" Payload)
  rm -rf "$OUT/ios/Payload"
}

linux_appimage() {
  need_os Linux "linux-appimage"
  ensure linux
  flutter build linux --release
  local arch dir bundle appdir bin
  arch="$(uname -m)"
  case "$arch" in aarch64) dir=arm64 ;; *) dir=x64 ;; esac
  bundle="build/linux/$dir/release/bundle"
  appdir="build/appimage/Penumbra.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/bin"
  cp -r "$bundle"/* "$appdir/usr/bin/"
  bin="$(find "$bundle" -maxdepth 1 -type f -perm -u+x ! -name '*.so*' -exec basename {} \; | head -1)"

  cat > "$appdir/AppRun" <<APPRUN
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\$0")")"
exec "\$HERE/usr/bin/$bin" "\$@"
APPRUN
  chmod +x "$appdir/AppRun"

  cat > "$appdir/penumbra.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Penumbra
Comment=Non-destructive photo editor
Exec=$bin
Icon=penumbra
Categories=Graphics;Photography;
Terminal=false
DESKTOP

  if command -v convert >/dev/null 2>&1; then
    convert assets/icon/icon.png -resize 512x512 "$appdir/penumbra.png"
  else
    cp assets/icon/icon.png "$appdir/penumbra.png"
  fi

  local tool
  tool="$(command -v appimagetool || true)"
  if [ -z "$tool" ]; then
    tool="build/appimagetool"
    curl -fsSL -o "$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$arch.AppImage"
    chmod +x "$tool"
  fi
  # --appimage-extract-and-run avoids needing FUSE (CI, containers).
  ARCH="$arch" "$tool" --appimage-extract-and-run "$appdir" "$OUT/Penumbra-$VERSION-$arch.AppImage"
}

android_xapk() {
  ensure android
  flutter build apk --release
  local apk pkg stage target size
  apk="build/app/outputs/flutter-apk/app-release.apk"
  pkg="$(grep -hoE 'applicationId *=? *"[^"]+"' android/app/build.gradle* 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  pkg="${pkg:-dev.penumbra.penumbra}"
  target="${TARGET_SDK:-35}"
  stage="$(mktemp -d)"
  cp "$apk" "$stage/$pkg.apk"
  cp assets/icon/icon.png "$stage/icon.png"
  size="$(wc -c < "$stage/$pkg.apk" | tr -d ' ')"
  cat > "$stage/manifest.json" <<JSON
{
  "xapk_version": 2,
  "package_name": "$pkg",
  "name": "Penumbra",
  "version_code": "$BUILD",
  "version_name": "$VERSION",
  "min_sdk_version": "24",
  "target_sdk_version": "$target",
  "permissions": ["android.permission.WRITE_EXTERNAL_STORAGE"],
  "total_size": $size,
  "icon": "icon.png",
  "split_configs": [],
  "split_apks": [{"file": "$pkg.apk", "id": "base"}]
}
JSON
  rm -f "$OUT/Penumbra-$VERSION.xapk"
  (cd "$stage" && zip -qr "$OUT/Penumbra-$VERSION.xapk" .)
  rm -rf "$stage"
}

windows_msi() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) ;;
    *) echo "error: windows-msi can only be built on Windows (run it in Git Bash)." >&2; exit 1 ;;
  esac
  command -v wix >/dev/null 2>&1 || {
    echo 'error: WiX CLI not found. Install it: dotnet tool install --global wix --version "4.*"' >&2
    exit 1
  }
  ensure windows
  flutter build windows --release
  local bundle="build/windows/x64/runner/Release"
  # Flutter apps need the Visual C++ runtime. Ship the three DLLs next to the exe
  # (app-local deployment) so the installer works on machines without it.
  for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
    [ -f "$bundle/$dll" ] || cp "/c/Windows/System32/$dll" "$bundle/" 2>/dev/null || true
  done
  # Relative paths: wix is a native Windows tool and does not know Git Bash paths.
  wix build tools/windows/Penumbra.wxs -arch x64 -sval \
    -d "Version=$VERSION.$BUILD" \
    -d "BundleDir=$bundle" \
    -d "IconFile=windows/runner/resources/app_icon.ico" \
    -o "dist/Penumbra-$VERSION-x64.msi"
}

[ "$#" -gt 0 ] || { sed -n '2,17p' "$0"; exit 1; }
for t in "$@"; do
  echo "==> $t"
  case "$t" in
    web-js) web_js ;;
    web-skwasm) web_skwasm ;;
    macos-app) macos_app ;;
    macos-dmg) macos_dmg ;;
    ios-app) ios_app ;;
    linux-appimage) linux_appimage ;;
    android-xapk) android_xapk ;;
    windows-msi) windows_msi ;;
    *) echo "unknown target: $t" >&2; exit 1 ;;
  esac
done
echo "Done. Output in $OUT"
