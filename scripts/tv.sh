#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_run_simulator_common.sh
source "$SCRIPT_DIR/_run_simulator_common.sh"

run_tvos_simulator \
  "Apple TV 4K (3rd generation)" \
  "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K"
