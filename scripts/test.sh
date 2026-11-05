#!/usr/bin/env bash
# 适配器的验证入口：编译 + 单元/行为测试（假 opencode，不依赖公网与模型）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cd "$ROOT"
cjpm build -j 8
cjpm test -j 4 --no-progress
echo "==> uhp-opencode: build + tests ok"
