#!/bin/sh
# Runs the protocol unit tests without Xcode's app-hosted test runner.
#
# The tests in F75DriverTests only exercise F75Protocol.swift, which has no
# dependencies beyond Foundation. This copies both into a throwaway Swift
# package and runs `swift test` there. See CLAUDE.md for why.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/f75-protocol-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/F75Driver" "$work/Tests/F75DriverTests"
cp "$root/F75Driver/Protocol/F75Protocol.swift" "$work/Sources/F75Driver/"
cp "$root/F75DriverTests/F75DriverTests.swift" "$work/Tests/F75DriverTests/"
cat > "$work/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "F75Driver",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "F75Driver", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "F75DriverTests", dependencies: ["F75Driver"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
MANIFEST

cd "$work"
swift test
