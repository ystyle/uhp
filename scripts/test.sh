#!/usr/bin/env bash
# 全产品验证入口：构建 + 全部成员测试（SDK 142 + opencode 11 + ACP 9）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cd "$ROOT"
cjpm build -j 8
cjpm test -j 4 --no-progress
echo "==> uhp monorepo: build + tests ok"
