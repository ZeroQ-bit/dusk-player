#!/bin/bash
set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ ! -d "Frameworks/VLCKit.xcframework" ]; then
    echo "Vendored VLCKit.xcframework is missing from the repository checkout."
    exit 1
fi

echo "Using vendored VLCKit.xcframework from the repository."
