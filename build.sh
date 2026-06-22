#!/bin/bash

# FluidVoice Build Profile Router
# Defaults to the private Fluid Intelligence build for local development.
#
# Usage:
#   ./build.sh                    # private FI build
#   ./build.sh fi                 # private FI build

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-fi}}"

case "${PROFILE}" in
    fi|private|dev|full)
        exec "${PROJECT_DIR}/build_with_FI_incremental.sh"
        ;;
    public|oss|incremental|fast)
        echo "Public/OSS builds are not available from this repo entrypoint."
        echo "Use the private Fluid Intelligence build: sh build_with_FI_incremental.sh"
        exit 1
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: fi/private/dev/full"
        exit 1
        ;;
esac
