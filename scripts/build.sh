#!/usr/bin/env bash
# 构建整个产品（SDK + 两个适配器成员）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cd "$ROOT"
cjpm build -j 8
