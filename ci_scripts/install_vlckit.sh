#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="${ROOT_DIR}/Frameworks/VLCKit.xcframework"
LICENSE_PATH="${ROOT_DIR}/Frameworks/VLCKit-LICENSE.txt"
SOURCE_DIR="${ROOT_DIR}/.build/vlckit-src"
VLCKIT_REPO_URL="https://code.videolan.org/videolan/VLCKit.git"
VLCKIT_REF="4.0.0a18"

# Manual maintenance script for refreshing the vendored VLCKit binary.
# CI consumes the checked-in xcframework and should not run this script.

has_pip_capable_vlckit() {
    [ -d "${FRAMEWORK_DIR}" ] && find "${FRAMEWORK_DIR}" -path "*Headers/VLCDrawable.h" -print -quit | grep -q .
}

thin_simulator_slice() {
    local simulator_dir="${FRAMEWORK_DIR}/ios-arm64_x86_64-simulator"
    local thin_simulator_dir="${FRAMEWORK_DIR}/ios-arm64-simulator"
    local simulator_framework="${thin_simulator_dir}/VLCKit.framework"
    local simulator_binary="${simulator_framework}/VLCKit"
    local thin_binary

    [ -d "${simulator_dir}" ] || return 0

    mv "${simulator_dir}" "${thin_simulator_dir}"

    thin_binary="$(mktemp "${ROOT_DIR}/.build/vlckit-simulator-XXXXXX")"
    xcrun lipo "${simulator_binary}" -thin arm64 -output "${thin_binary}"
    mv "${thin_binary}" "${simulator_binary}"
    chmod 755 "${simulator_binary}"

    plutil -replace 'AvailableLibraries.1.LibraryIdentifier' -string 'ios-arm64-simulator' "${FRAMEWORK_DIR}/Info.plist"
    plutil -replace 'AvailableLibraries.1.SupportedArchitectures' -json '["arm64"]' "${FRAMEWORK_DIR}/Info.plist"

    codesign --force --sign - --timestamp=none "${simulator_framework}" >/dev/null
}

if has_pip_capable_vlckit; then
    echo "PiP-capable VLCKit already present."
    exit 0
fi

echo "Building VLCKit ${VLCKIT_REF} from source..."

rm -rf "${FRAMEWORK_DIR}" "${SOURCE_DIR}"
mkdir -p "${ROOT_DIR}/Frameworks" "${ROOT_DIR}/.build"

git clone --depth 1 --branch "${VLCKIT_REF}" "${VLCKIT_REPO_URL}" "${SOURCE_DIR}"

(
    cd "${SOURCE_DIR}"
    ./compileAndBuildVLCKit.sh -f -r
)

cp -R "${SOURCE_DIR}/build/iOS/VLCKit.xcframework" "${FRAMEWORK_DIR}"
find "${FRAMEWORK_DIR}" -type d -name dSYMs -prune -exec rm -rf {} +
plutil -remove 'AvailableLibraries.0.DebugSymbolsPath' "${FRAMEWORK_DIR}/Info.plist"
plutil -remove 'AvailableLibraries.1.DebugSymbolsPath' "${FRAMEWORK_DIR}/Info.plist"
thin_simulator_slice
cp "${SOURCE_DIR}/COPYING" "${LICENSE_PATH}"

echo "PiP-capable VLCKit installed at ${FRAMEWORK_DIR}."
