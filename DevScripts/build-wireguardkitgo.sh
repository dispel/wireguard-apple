#!/usr/bin/env bash
# Build WireGuardKitGo robustly from Xcode or Terminal.
# - Finds the correct WireGuardKitGo dir (repo-local or DerivedData)
# - Ensures 'go' is visible to Xcode and GOROOT is non-empty
# - Invokes make via xcrun (portable across Xcode/CLT setups)
set -euo pipefail

# Ensure Homebrew paths are visible in Xcode's env
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# 1) Locate 'go' (honor GO env var if the caller set it)
if [[ -z "${GO:-}" ]]; then
  GO="$(command -v go || true)"
fi
if [[ -z "${GO:-}" ]]; then
  echo "❌ 'go' not found on PATH. Install Go or set GO=/path/to/go before building." >&2
  exit 1
fi
echo "→ GO = $GO"
"$GO" version || true

# 2) Verify GOROOT (Makefile requires this to be non-empty)
GOROOT="$("$GO" env GOROOT 2>/dev/null || true)"
echo "→ GOROOT = ${GOROOT:-<empty>}"
if [[ -z "$GOROOT" ]]; then
  echo "❌ 'go env GOROOT' is empty; WireGuardKitGo Makefile will fail. Fix your Go install." >&2
  exit 1
fi

# 3) Resolve WireGuardKitGo working directory
REPO_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.."; pwd)}"
CANDIDATE_1="$REPO_ROOT/Sources/WireGuardKitGo"  # repo-local (preferred)
CANDIDATE_2=""                                    # SwiftPM checkout in DerivedData (older layout)
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
  echo "   Tried:" >&2
  echo "     $CANDIDATE_1" >&2
  [[ -n "$CANDIDATE_2" ]] && echo "     $CANDIDATE_2" >&2
  exit 1
fi

echo "→ Building in: $WG_DIR"
cd "$WG_DIR"

# 4) Discover 'make' via xcrun (ensures the Xcode toolchain is used)
MAKE_PATH="$(/usr/bin/xcrun --find make)"
echo "→ make = $MAKE_PATH"
file "$MAKE_PATH" || true

# 5) Run make. Pass GO explicitly; enable verbosity. Forward any extra args.
MAKE_ARGS=( "V=1" "GO=$GO" )
if [[ $# -gt 0 ]]; then
  MAKE_ARGS+=( "$@" )
fi

set -x
/usr/bin/xcrun make "${MAKE_ARGS[@]}"
