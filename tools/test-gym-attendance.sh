#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftc >/dev/null; then
    echo "Gym attendance checks require a Swift compiler (swiftc)." >&2
    exit 1
fi
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc FocusLift/Models/Models.swift FocusLift/Models/GymAttendance.swift \
    tests/GymAttendanceRegression.swift -o "$build_dir/test-gym-attendance"
"$build_dir/test-gym-attendance"
