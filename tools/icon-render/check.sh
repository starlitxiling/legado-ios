#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/tmp
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
export TMPDIR="$PWD/.build/tmp"
swift test --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
.build/debug/IconRender Tests/IconRendererTests/Fixtures/res ../../App/Resources/AlternateIcons
