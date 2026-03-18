#!/bin/bash
set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ ! -d "Frameworks/VLCKit.xcframework" ]; then
    echo "Vendored iOS VLCKit.xcframework is missing from the repository checkout."
    exit 1
fi

if [ ! -d "Frameworks/VLCKit-tvOS.xcframework" ]; then
    echo "Vendored tvOS VLCKit-tvOS.xcframework is missing from the repository checkout."
    exit 1
fi

echo "Using vendored iOS and tvOS VLCKit frameworks from the repository."
