#!/bin/bash
set -eu

b13b_root="$(cd "$(dirname "$0")/../.." && pwd)"
run_suite() {
    cd "$1"
    mkdir -p .build/tmp
    if CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
        SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" \
        TMPDIR="$PWD/.build/tmp" \
        swift test --cache-path "$PWD/.build/cache" --disable-sandbox \
        --disable-automatic-resolution --skip-update --filter "$2" > .build/b13b-green.log 2>&1; then
        tail -10 .build/b13b-green.log
    else
        tail -10 .build/b13b-green.log
        return 1
    fi
}
run_suite "$b13b_root/Packages/LegadoCore" 'BackupSelectionTests|BackupExportTests|BackupTests|BackupResourceTests|WebDavSettingsTests|ImageRetentionTests|CoverConfigurationTests'
run_suite "$b13b_root/tools/appcore-check" 'AppPreferencesTests|CoverSettingsTests|LauncherIconTests|BackupPreferenceTests|BackupReviewFixTests|SettingsBackupTests|ReaderTests|ReaderRevisionTests|ReaderWebDavTests|MangaReaderModelTests'
