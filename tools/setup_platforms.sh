#!/usr/bin/env bash
# Creates any missing Flutter platform folders and applies the small native
# patches this app needs (permissions, minimum OS versions).
# Usage: tools/setup_platforms.sh [android,ios,web,windows,macos,linux]
set -euo pipefail

PLATFORMS="${1:-android,ios,web,windows,macos,linux}"

missing=0
for p in ${PLATFORMS//,/ }; do
  [ -d "$p" ] || missing=1
done
if [ "$missing" = 1 ]; then
  flutter create --project-name penumbra --org dev.penumbra --platforms="$PLATFORMS" .
  rm -f test/widget_test.dart
fi

# ---- Android: minSdk 24 (ML Kit), legacy storage permission for API <= 28 ----
if [ -d android ]; then
  gradle="$(ls android/app/build.gradle.kts android/app/build.gradle 2>/dev/null | head -1 || true)"
  if [ -n "$gradle" ]; then
    sed -i.bak -E 's/minSdk = flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion flutter\.minSdkVersion/minSdkVersion 24/' "$gradle"
    rm -f "$gradle.bak"
  fi
  manifest=android/app/src/main/AndroidManifest.xml
  if ! grep -q WRITE_EXTERNAL_STORAGE "$manifest"; then
    sed -i.bak 's|<application|<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>\n    <application|' "$manifest"
    rm -f "$manifest.bak"
  fi
fi

# ---- iOS: ML Kit needs iOS 15.5+, usage descriptions for photos/camera ----
if [ -d ios ]; then
  sed -i.bak -E "s/^#? *platform :ios, .*/platform :ios, '15.5'/" ios/Podfile
  rm -f ios/Podfile.bak
  if [ -x /usr/libexec/PlistBuddy ]; then
    plist=ios/Runner/Info.plist
    set_key() {
      /usr/libexec/PlistBuddy -c "Delete :$1" "$plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
    }
    set_key NSPhotoLibraryUsageDescription "Open photos to edit them."
    set_key NSPhotoLibraryAddUsageDescription "Save your edited photos."
    set_key NSCameraUsageDescription "Take photos to edit."
  fi
fi

# ---- macOS: file open/save dialogs need the user-selected entitlement ----
if [ -d macos ]; then
  sed -i.bak -E "s/^#? *platform :osx, .*/platform :osx, '11.0'/" macos/Podfile
  rm -f macos/Podfile.bak
  if [ -x /usr/libexec/PlistBuddy ]; then
    for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
      [ -f "$f" ] || continue
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.files.user-selected.read-write" "$f" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :com.apple.security.files.user-selected.read-write bool true" "$f"
    done
  fi
fi

echo "Platforms ready: $PLATFORMS"
