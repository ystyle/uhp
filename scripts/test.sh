#!/usr/bin/env bash
# 本仓的「一条命令验证」：编译 + 单测。
#
# 约定（与工作区其它仓一致）：
#   - 仓颉工具链由 cjvs 管理，先加载 1.2.0 与 stdx 的 LD_LIBRARY_PATH；
#   - -j 8：单模块仓，编译并发度不影响测试进程；不要开更大（CI 机器内存有限）；
#   - 任一步失败即非零退出（set -e），CI 直接看退出码，不解析日志。
#
# 不包含：schema 制品校验（tools/check_schema_sync.py，单独一步）、
#         官方一致性套件（scripts/conformance.sh，未落地）、e2e（需要真实进程/网络）。
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> 加载仓颉环境（cjvs env / stdx-env）"
# shellcheck disable=SC1090
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"

echo "==> cjpm build -j 8"
cjpm build -j 8

echo "==> cjpm test -j 8 --no-progress"
cjpm test -j 8 --no-progress

echo "==> all green"
