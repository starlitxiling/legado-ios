#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_DIR}/.build"
DIST_DIR="${REPO_DIR}/dist"
CONFIGURATION="${CONFIGURATION:-Release}"
export CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/clang-cache"

command -v xcodegen >/dev/null
command -v xcodebuild >/dev/null
GIT_HASH="$(git -C "${REPO_DIR}" rev-parse --short HEAD)"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
STAGING_DIR="$(mktemp -d "${BUILD_DIR}/ipa.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcodegen --spec "${REPO_DIR}/App/project.yml"
xcodebuild -project "${REPO_DIR}/App/Legado.xcodeproj" -scheme Legado \
    -destination 'generic/platform=iOS' -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -archivePath "${STAGING_DIR}/Legado.xcarchive" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive

# 独立暂存目录避免混入上一次打包的应用。
APP_PATH="${STAGING_DIR}/Legado.xcarchive/Products/Applications/Legado.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Info.plist")"
case "${VERSION}" in
    ''|*[!0-9A-Za-z._-]*)
        printf '应用版本号为空或含非法文件名字符：%s\n' "${VERSION}" >&2
        exit 1
        ;;
esac
IPA_NAME="Legado-${VERSION}-${GIT_HASH}.ipa"
mkdir -p "${STAGING_DIR}/Payload"
ditto "${APP_PATH}" "${STAGING_DIR}/Payload/Legado.app"
(cd "${STAGING_DIR}" && /usr/bin/zip -qry "${IPA_NAME}" Payload)
mv -f "${STAGING_DIR}/${IPA_NAME}" "${DIST_DIR}/${IPA_NAME}"
IPA_SIZE="$(stat -f '%z' "${DIST_DIR}/${IPA_NAME}")"
printf '未签名安装包：%s\n大小：%s 字节\n' "${DIST_DIR}/${IPA_NAME}" "${IPA_SIZE}"
