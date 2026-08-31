#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
core_directory="${project_directory}/spotify-core"
rustup_binary="${RUSTUP_BIN:-$(command -v rustup)}"
cargo_binary="${CARGO_BIN:-$(${rustup_binary} which --toolchain stable cargo)}"
rustc_binary="${RUSTC_BIN:-$(${rustup_binary} which --toolchain stable rustc)}"

targets=(
    aarch64-apple-ios
    aarch64-apple-ios-sim
)

"${rustup_binary}" target add --toolchain stable "${targets[@]}"

cd "${core_directory}"

RUSTC="${rustc_binary}" "${cargo_binary}" build --release

for target in "${targets[@]}"; do
    RUSTC="${rustc_binary}" "${cargo_binary}" build --release --target "${target}"
done

print "Built SpotifyCore static libraries for macOS, iPhone, and Apple-silicon iOS Simulator."
