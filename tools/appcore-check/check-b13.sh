#!/bin/bash
set -eu

b13_root="$(cd "$(dirname "$0")/../.." && pwd)"

run_suite() {
    cd "$1"
    mkdir -p .build/tmp
    if CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" \
        TMPDIR="$PWD/.build/tmp" \
        swift test --cache-path "$PWD/.build/cache" --disable-sandbox \
        --disable-automatic-resolution --skip-update --filter "$2" > .build/b13-green.log 2>&1; then
        tail -10 .build/b13-green.log
    else
        tail -10 .build/b13-green.log
        return 1
    fi
}

run_suite "$b13_root/Packages/LegadoCore" 'BackupExportTests|BackupTests|BackupReviewTests|WebDavTests|WebDavLimitTests'
run_suite "$b13_root/tools/appcore-check" 'BackupPreferenceTests|BackupReviewFixTests|SettingsBackupTests|ReaderTests|ReaderRevisionTests|BookshelfAdvancedTests'
