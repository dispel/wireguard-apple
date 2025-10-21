#!/usr/bin/env bash
set -euo pipefail

# Ensure Homebrew paths are visible in Xcode's env
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Locate go
if [[ -z "${GO:-}" ]]; then
  GO="$(command -v go || true)"
fi
if [[ -z "${GO:-}" ]]; then
  echo "❌ 'go' not found on PATH. Install Go or set GO=/path/to/go." >&2
  exit 1
fi
echo "→ GO = $GO"
"$GO" version || true

# Verify GOROOT
GOROOT="$("$GO" env GOROOT 2>/dev/null || true)"
echo "→ GOROOT = ${GOROOT:-<empty>}"
if [[ -z "$GOROOT" ]]; then
  echo "❌ 'go env GOROOT' is empty; fix your Go install." >&2
  exit 1
fi

# Find WireGuardKitGo
REPO_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.."; pwd)}"
CANDIDATE_1="$REPO_ROOT/Sources/WireGuardKitGo"
CANDIDATE_2=""
if [[ -n "${BUILD_DIR:-}" ]]; then
  CANDIDATE_2="${BUILD_DIR%Build/*}SourcePackages/checkouts/wireguard-apple/Sources/WireGuardKitGo"
fi

WG_DIR=""
if [[ -f "$CANDIDATE_1/Makefile" ]]; then
  WG_DIR="$CANDIDATE_1"
elif [[ -n "$CANDIDATE_2" && -f "$CANDIDATE_2/Makefile" ]]; then
  WG_DIR="$CANDIDATE_2"
fi
if [[ -z "$WG_DIR" ]]; then
  echo "❌ Could not find WireGuardKitGo/Makefile." >&2
  exit 1
fi
echo "→ Building in: $WG_DIR"
cd "$WG_DIR"

# Choose SDK from PLATFORM_NAME
case "${PLATFORM_NAME:-}" in
  iphonesimulator*) SDK=iphonesimulator; OUT_SUB=ios-simulator-arm64 ;;
  iphoneos*)        SDK=iphoneos;        OUT_SUB=ios-device-arm64 ;;
  macosx*)          SDK=macosx;          OUT_SUB=macos-arm64 ;; # just in case
  *) echo "❌ Unknown PLATFORM_NAME='${PLATFORM_NAME:-<empty>}'"; exit 1;;
esac
echo "→ SDK = $SDK  (PLATFORM_NAME=${PLATFORM_NAME})"

# If building for iOS (simulator or device), ensure Go builds with the 'ios' tag
case "${PLATFORM_NAME:-}" in
  iphonesimulator*|iphoneos*)
    export GOFLAGS="${GOFLAGS:-} -tags=ios"
    export CGO_ENABLED=1
    ;;
esac

# Use make via xcrun; pass GO and the chosen SDK so the Makefile emits the right slice
MAKE_PATH="$(/usr/bin/xcrun --find make)"
echo "→ make = $MAKE_PATH"
/usr/bin/xcrun make V=1 GO="$GO" SDK="$SDK"

# Prefer the location the Makefile already wrote to:
if [[ -n "${BUILT_PRODUCTS_DIR:-}" && -f "$BUILT_PRODUCTS_DIR/libwg-go.a" ]]; then
  echo "→ Found: $BUILT_PRODUCTS_DIR/libwg-go.a"
  # (Optional) echo slice info:
  file "$BUILT_PRODUCTS_DIR/libwg-go.a" || true
  exit 0
fi

# Fallback: search legacy/output paths if the above wasn’t produced
CAND_LIBS=(
  "$WG_DIR/build/ios-simulator-arm64/libwg-go.a"
  "$WG_DIR/build/iphonesimulator/libwg-go.a"
  "$WG_DIR/build/libwg-go.a"
)
for p in "${CAND_LIBS[@]}"; do
  if [[ -f "$p" ]]; then
    echo "→ Found: $p"
    # ensure linker finds it even if not in BUILT_PRODUCTS_DIR
    cp -f "$p" "$BUILT_PRODUCTS_DIR/libwg-go.a"
    echo "→ Copied to: $BUILT_PRODUCTS_DIR/libwg-go.a"
    exit 0
  fi
done

echo "❌ libwg-go.a not found after build. Checked BUILT_PRODUCTS_DIR and fallback locations." >&2
exit 1


# Locate produced lib (common layouts below; adjust if your Makefile differs)
CAND_LIBS=(
  "$WG_DIR/build/$OUT_SUB/libwg-go.a"
  "$WG_DIR/build/$SDK/libwg-go.a"
  "$WG_DIR/build/libwg-go.a"
)
FOUND_LIB=""
for p in "${CAND_LIBS[@]}"; do
  if [[ -f "$p" ]]; then FOUND_LIB="$p"; break; fi
done
if [[ -z "$FOUND_LIB" ]]; then
  echo "❌ libwg-go.a not found after build. Built files:" >&2
  find "$WG_DIR/build" -type f -maxdepth 3 -print 2>/dev/null || true
  exit 1
fi
echo "→ Found: $FOUND_LIB"

# Copy to BUILT_PRODUCTS_DIR so -L .../Debug-iphonesimulator + -lwg-go works
DEST_DIR="${BUILT_PRODUCTS_DIR:-$REPO_ROOT/build}"
mkdir -p "$DEST_DIR"
cp -f "$FOUND_LIB" "$DEST_DIR/libwg-go.a"
echo "→ Copied to: $DEST_DIR/libwg-go.a"
