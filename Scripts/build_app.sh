#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="${PROJECT_DIR}/.build-app"
CACHE_DIR="${PROJECT_DIR}/.build-cache"
APP_DIR="${PROJECT_DIR}/dist/秋招助手.app"

mkdir -p "${CACHE_DIR}/clang" "${CACHE_DIR}/swift" "${PROJECT_DIR}/dist"

env \
  CLANG_MODULE_CACHE_PATH="${CACHE_DIR}/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="${CACHE_DIR}/swift" \
  swift build \
    --disable-sandbox \
    --scratch-path "${BUILD_DIR}" \
    -c release

BIN_DIR=$(env \
  CLANG_MODULE_CACHE_PATH="${CACHE_DIR}/clang" \
  SWIFTPM_MODULECACHE_OVERRIDE="${CACHE_DIR}/swift" \
  swift build \
    --disable-sandbox \
    --scratch-path "${BUILD_DIR}" \
    -c release \
    --show-bin-path)

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/AutumnJobs" "${APP_DIR}/Contents/MacOS/AutumnJobs"
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
chmod +x "${APP_DIR}/Contents/MacOS/AutumnJobs"

codesign --force --deep --sign - "${APP_DIR}"

echo "Built: ${APP_DIR}"
