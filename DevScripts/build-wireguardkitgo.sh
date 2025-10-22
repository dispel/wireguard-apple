#!/usr/bin/env bash
# Build WireGuardKitGo's libwg-go.a for the active Apple platform (macOS/iOS sim/device).
# Emits libwg-go.a into $BUILT_PRODUCTS_DIR so Xcode can link it with -lwg-go.

set -Eeuo pipefail

### ---- logging / error handling ------------------------------------------------
SECTION() { echo -e "\n==> $*"; }
NOTE()    { echo "→ $*"; }
FAIL()    { echo "❌ $*" >&2; exit 1; }

trap 'FAIL "Error at line $LINENO: ${BASH_COMMAND:-?}"' ERR

### ---- env sanity --------------------------------------------------------------
# Make sure Homebrew tools (go, rsync, etc.) are in PATH when launched by Xcode
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SECTION "Go toolchain"
GO="${GO:-$(command -v go || true)}"
[[ -n "${GO}" ]] || FAIL "'go' not found on PATH. Install Go or set GO=/path/to/go."
NOTE "GO = $GO"
"$GO" version || true

GOROOT="$("$GO" env GOROOT 2>/dev/null || true)"
NOTE "GOROOT = ${GOROOT:-<empty>}"
[[ -n "$GOROOT" ]] || FAIL "'go env GOROOT' is empty; fix your Go install."

### ---- locate WireGuardKitGo ---------------------------------------------------
SECTION "Locate WireGuardKitGo"
REPO_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.."; pwd)}"

CANDIDATE_1="$REPO_ROOT/Sources/WireGuardKitGo"
CANDIDATE_2=""
if [[ -n "${BUILD_DIR:-}" ]]; then
  # If building from an SPM checkout in DerivedData
  CANDIDATE_2="${BUILD_DIR%Build/*}SourcePackages/checkouts/wireguard-apple/Sources/WireGuardKitGo"
fi

WG_DIR=""
if [[ -f "$CANDIDATE_1/Makefile" ]]; then
  WG_DIR="$CANDIDATE_1"
elif [[ -n "$CANDIDATE_2" && -f "$CANDIDATE_2/Makefile" ]]; then
  WG_DIR="$CANDIDATE_2"
else
  FAIL "Could not find WireGuardKitGo/Makefile"
fi

NOTE "Building in: $WG_DIR"
cd "$WG_DIR"

### ---- select SDK / platform ---------------------------------------------------
SECTION "Select SDK"
case "${PLATFORM_NAME:-}" in
  iphonesimulator*) SDK=iphonesimulator ;;
  iphoneos*)        SDK=iphoneos ;;
  macosx*)          SDK=macosx ;;
  *)                FAIL "Unknown PLATFORM_NAME='${PLATFORM_NAME:-<empty>}'" ;;
esac
NOTE "SDK = $SDK  (PLATFORM_NAME=${PLATFORM_NAME:-<unset>})"

# iOS (sim/device) needs the 'ios' build tag so cgo pulls in the correct runtime bits.
case "${PLATFORM_NAME:-}" in
  iphonesimulator*|iphoneos*)
    export GOFLAGS="${GOFLAGS:-} -tags=ios"
    export CGO_ENABLED=1
    ;;
esac

### ---- build via Makefile ------------------------------------------------------
SECTION "make"
MAKE_PATH="$(/usr/bin/xcrun --find make)"
NOTE "make = $MAKE_PATH"
/usr/bin/xcrun make V=1 GO="$GO" SDK="$SDK"

### ---- locate output + finalize ------------------------------------------------
SECTION "Find output"

# 1) Prefer what the Makefile already wrote (this is where your Xcode link step looks)
if [[ -n "${BUILT_PRODUCTS_DIR:-}" && -f "$BUILT_PRODUCTS_DIR/libwg-go.a" ]]; then
  NOTE "Found: $BUILT_PRODUCTS_DIR/libwg-go.a"
  file "$BUILT_PRODUCTS_DIR/libwg-go.a" || true
  exit 0
fi

# 2) Fallbacks for older/alternate layouts; copy into BUILT_PRODUCTS_DIR for the linker
CAND_LIBS=(
  "$WG_DIR/build/ios-simulator-arm64/libwg-go.a"
  "$WG_DIR/build/iphonesimulator/libwg-go.a"
  "$WG_DIR/build/ios-device-arm64/libwg-go.a"
  "$WG_DIR/build/iphoneos/libwg-go.a"
  "$WG_DIR/build/macos-arm64/libwg-go.a"
  "$WG_DIR/build/macosx/libwg-go.a"
  "$WG_DIR/build/libwg-go.a"
)

FOUND=""
for p in "${CAND_LIBS[@]}"; do
  if [[ -f "$p" ]]; then FOUND="$p"; break; fi
done

if [[ -n "$FOUND" ]]; then
  NOTE "Found: $FOUND"
  DEST="${BUILT_PRODUCTS_DIR:-$REPO_ROOT/build}"
  mkdir -p "$DEST"
  cp -f "$FOUND" "$DEST/libwg-go.a"
  NOTE "Copied to: $DEST/libwg-go.a"
  file "$DEST/libwg-go.a" || true
  exit 0
fi

# 3) Still nothing? Show what exists to help debugging.
FAIL "libwg-go.a not found after build. Checked BUILT_PRODUCTS_DIR and fallback locations."
