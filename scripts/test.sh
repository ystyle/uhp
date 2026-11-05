#!/usr/bin/env bash
# 适配器验证入口：编译（含假 ACP agent） + 测试（真实 stdio JSON-RPC，不依赖模型/网络）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cd "$ROOT"
cjpm build -j 8
cjpm test -j 4 --no-progress
echo "==> uhp-acp: build + tests ok"
