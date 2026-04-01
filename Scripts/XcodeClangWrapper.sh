#!/bin/bash

set -euo pipefail

REAL_CLANG="${AETHER_REAL_CLANG:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang}"

exec "$REAL_CLANG" "$@"
