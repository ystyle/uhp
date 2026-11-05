#!/usr/bin/env bash
# 官方 UHP 一致性套件跑本仓的 SUT，报告落到 docs/conformance/。
#
# 用法：
#   bash scripts/conformance.sh [class]            # class = core（默认）| extended | full
#   UHP_CONFORMANCE_DIR=/path/to/conformance bash scripts/conformance.sh core
#
# 前置：
#   1) 套件不在 PyPI，需把上游 protocol/conformance 拿出来（含 uhp_conformance/ 目录与 jsonschema 依赖）。
#      本机放在 .uhp-research/conformance（脚本会自动识别），也可用 UHP_CONFORMANCE_DIR 指定。
#   2) 套件版本记进报告（suite_version），文件名为 <suite_version>-<class>.json。
set -euo pipefail

CLASS="${1:-core}"
MEMBER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$MEMBER_ROOT/.." && pwd)"   # monorepo 根（构建产物在根 target/）
CONF_DIR="${UHP_CONFORMANCE_DIR:-$ROOT/../.uhp-research/conformance}"
PORT="${UHP_SUT_PORT:-8471}"
API_KEY="${UHP_API_KEY:-dev-token}"

[ -d "$CONF_DIR/uhp_conformance" ] || { echo "找不到一致性套件：$CONF_DIR/uhp_conformance" >&2; exit 2; }
[ -x "$CONF_DIR/venv/bin/python" ] || { echo "缺少 venv：$CONF_DIR/venv（需要 jsonschema>=4）" >&2; exit 2; }

echo "==> 构建 SUT"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
(cd "$ROOT" && cjpm build -j 8)

echo "==> 启动 SUT（端口 $PORT）"
"$ROOT/target/release/bin/uhp.examples.conformance_sut" "$PORT" > /tmp/uhp-sut.log 2>&1 &
SUT_PID=$!
trap 'kill $SUT_PID 2>/dev/null || true' EXIT

# 就绪等待：轮询 discovery，不用 sleep 硬等
ready=0
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/v1/uhp" || true)
  if [ "$code" = "200" ]; then ready=1; break; fi
  sleep 0.1
done
[ "$ready" = "1" ] || { echo "SUT 未就绪：见 /tmp/uhp-sut.log" >&2; exit 3; }

echo "==> 跑一致性套件：class=$CLASS"
cd "$CONF_DIR"
cat > .run_conformance.py <<'PY'
import sys
from uhp_conformance.cli import main
sys.exit(main())
PY
REPORT="$MEMBER_ROOT/docs/conformance/pending-$CLASS.json"

# 失败也要把报告落盘——报告最该在失败时存在。先吞退出码，落盘后再按它退出。
set +e
# 插件的 MCP server 指向 SUT 进程内的本地 fixture（port+1）：CI 不依赖公网
PYTHONPATH=. ./venv/bin/python .run_conformance.py \
  --base-url "http://127.0.0.1:$PORT" --api-key "$API_KEY" \
  --plugin-mcp-url "http://127.0.0.1:$((PORT + 1))/mcp" \
  --class "$CLASS" --task-timeout 60 --plain --json "$REPORT"
SUITE_EXIT=$?
set -e

# 报告按 <suite_version>-<class>.json 落盘（suite_version 是「我是哪个套件测的」的证据）
VERSION=$(python3 -c "import json,sys;print(json.load(open('$REPORT'))['suite_version'])")
mkdir -p "$MEMBER_ROOT/docs/conformance"
mv "$REPORT" "$MEMBER_ROOT/docs/conformance/$VERSION-$CLASS.json"
echo "==> 报告：$MEMBER_ROOT/docs/conformance/$VERSION-$CLASS.json（suite exit=$SUITE_EXIT）"
exit "$SUITE_EXIT"
