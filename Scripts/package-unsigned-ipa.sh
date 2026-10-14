#!/usr/bin/env bash
# Build an unsigned iOS device IPA for AltStore or Sideloadly.
# Requires Xcode on macOS (the GitHub Actions workflow provides that).
# Signing is left to the free Apple ID on the Windows PC. This script
# refuses a build that still carries a provisioning profile or entitlements.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

bundle_id="${BUNDLE_ID:-personal.roomremote}"
derived="${DERIVED_DATA_PATH:-$root/build/DerivedData}"
out_dir="${OUT_DIR:-$root/dist}"
app_name="RoomRemote"
ipa="$out_dir/${app_name}-unsigned.ipa"

if [[ ! "$bundle_id" =~ ^[A-Za-z][A-Za-z0-9.-]+$ ]]; then
  echo "Bundle id must look like personal.roomremote (got: $bundle_id)" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is not on this machine. Run .github/workflows/ipa.yml on a GitHub-hosted macOS runner." >&2
  exit 1
fi

rm -rf "$derived"
mkdir -p "$out_dir"

echo "Building $app_name ($bundle_id) without a signature"
xcodebuild \
  -project RoomRemote.xcodeproj \
  -scheme RoomRemote \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ENABLE_DEBUG_DYLIB=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build

app=""
while IFS= read -r candidate; do
  app="$candidate"
  break
done < <(find "$derived/Build/Products" -type d -name "${app_name}.app" -path '*iphoneos*')
if [[ -z "$app" || ! -d "$app" ]]; then
  echo "Release device app was not produced under $derived/Build/Products" >&2
  find "$derived/Build/Products" -name '*.app' -maxdepth 3 >&2 || true
  exit 1
fi

echo "Packaging $app"
rm -rf "$app/_CodeSignature"
rm -f "$app/embedded.mobileprovision"
if codesign -d "$app" >/dev/null 2>&1; then
  codesign --remove-signature "$app"
fi

signing_bits="$(find "$app" \( -name '*.entitlements' -o -name '*.xcent' -o -name 'embedded.mobileprovision' -o -name '_CodeSignature' \) -print)"
if [[ -n "$signing_bits" ]]; then
  echo "Refusing to package a build that still has entitlements or a provisioning profile." >&2
  printf '%s\n' "$signing_bits" >&2
  exit 1
fi

if codesign -d "$app" >/dev/null 2>&1; then
  echo "The app is still signed. Sideloadly and AltStore need an unsigned IPA." >&2
  codesign -d --entitlements :- "$app" >&2 || true
  exit 1
fi

info="$app/Info.plist"
got_id="$(plutil -extract CFBundleIdentifier raw "$info")"
if [[ "$got_id" != "$bundle_id" ]]; then
  echo "Built bundle id is $got_id, expected $bundle_id" >&2
  exit 1
fi

min_os="$(plutil -extract MinimumOSVersion raw "$info")"
case "$min_os" in
  17|17.*) ;;
  *)
    echo "MinimumOSVersion is $min_os, expected 17.x" >&2
    exit 1
    ;;
esac

platform="$(plutil -extract DTPlatformName raw "$info")"
if [[ "$platform" != "iphoneos" ]]; then
  echo "Build platform is $platform, expected iphoneos" >&2
  exit 1
fi

executable="$(plutil -extract CFBundleExecutable raw "$info")"
binary_kind="$(file "$app/$executable")"
case "$binary_kind" in
  *arm64*) ;;
  *)
    echo "Executable is not an arm64 device binary:" >&2
    printf '%s\n' "$binary_kind" >&2
    exit 1
    ;;
esac

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload"
cp -R "$app" "$stage/Payload/"
xattr -cr "$stage/Payload" || true

rm -f "$ipa"
ditto -c -k --sequesterRsrc --keepParent "$stage/Payload" "$ipa"

listing="$(unzip -l "$ipa")"
case "$listing" in
  *"Payload/${app_name}.app/Info.plist"*) ;;
  *)
    echo "IPA is missing Payload/${app_name}.app/Info.plist" >&2
    exit 1
    ;;
esac

echo "Wrote $ipa ($(du -h "$ipa" | awk '{print $1}'))"
echo "Bundle id: $bundle_id"
echo "Minimum iOS: $min_os"
