#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftc >/dev/null; then
    echo "Voice checks require macOS with Xcode Command Line Tools (swiftc)." >&2
    exit 1
fi
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc FocusLift/Models/Models.swift FocusLift/Audio/Phrases.swift \
    FocusLift/Audio/ElevenLabs.swift tests/VoiceRegression.swift -o "$build_dir/test-voice"
"$build_dir/test-voice"
