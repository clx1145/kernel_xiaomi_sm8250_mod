#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1-}" in
    nova)
        # The builtin-new branch contains upstream's Non-GKI compatibility.
        repo=https://github.com/SukiSU-Nova/SukiSU-Nova.git
        revision=5a3ec4145059ed2c4f22c70a16a28a616e104c33
        checkout=KernelSU-Nova
        driver=drivers/sukisu_nova
        ;;
    ultra)
        repo=https://github.com/ApartTUSITU/SukiSU-Ultra.git
        revision=5dab4f278eaaadd44883dda6e3d826f56e47c450
        checkout=KernelSU
        driver=drivers/kernelsu
        ;;
    *)
        echo "Usage: $0 nova|ultra" >&2
        exit 2
        ;;
esac

target="../$checkout/kernel"
if [[ -L "$driver" && "$(readlink "$driver")" == "$target" ]]; then
    linked=true
elif [[ -e "$driver" || -L "$driver" ]]; then
    echo "Cannot install $1: $driver already exists with a different target." >&2
    exit 1
else
    linked=false
fi

if [[ ! -e "$checkout" && ! -L "$checkout" ]]; then
    staging=$(mktemp -d ".$checkout.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    git clone --no-checkout "$repo" "$staging"
    git -C "$staging" checkout --detach "$revision"
    mv -T -- "$staging" "$checkout"
fi

if [[ ! -d "$checkout/.git" ||
      "$(git -C "$checkout" rev-parse HEAD)" != "$revision" ||
      ! -f "$checkout/kernel/Kconfig" ]]; then
    echo "Cannot install $1: $checkout must be at $revision." >&2
    exit 1
fi

if [[ "$linked" == false ]]; then
    ln -sT -- "$target" "$driver"
fi
