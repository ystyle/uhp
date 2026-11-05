#!/usr/bin/env bash
# 真实链路冒烟：opencode 2.x + 一个可用模型，跑一个 UHP 任务。
#
# 前置：
#   1. 本机有 opencode v2 可执行（修改 OPENCODE_BIN 指向它）
#   2. 已配置可用 provider（OPENCODE_SERVER_PASSWORD 固定成 splice-token）
# 用法：
#   bash scripts/real-smoke.sh [modelID] [providerID]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCDIR="${OCDIR:-$ROOT/../../.uhp-research/oc2}"
OPENCODE_BIN="${OPENCODE_BIN:-$OCDIR/pkg/node_modules/@opencode/cli-linux-x64/bin/opencode}"
MODEL="${1:-deepseek-v4.1-flash-free}"
PROVIDER="${2:-opencode}"
PORT="${UHP_PORT:-8487}"
OC_PORT="${OC_PORT:-4776}"
WS="${WS:-$OCDIR/ws}"
LOGS="$OCDIR/logs"

[ -x "$OPENCODE_BIN" ] || { echo "找不到 opencode v2：$OPENCODE_BIN" >&2; exit 2; }
[ -d "$WS" ] || { echo "找不到工作目录：$WS" >&2; exit 2; }
mkdir -p "$LOGS"

cd "$ROOT"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cjpm build -j 8

echo "==> 起 opencode serve :$OC_PORT"
export XDG_CONFIG_HOME="$OCDIR/config" XDG_CACHE_HOME="$OCDIR/cache"
export XDG_DATA_HOME="$OCDIR/data" XDG_STATE_HOME="$OCDIR/state"
export OPENCODE_SERVER_PASSWORD=splice-token
(cd "$WS" && "$OPENCODE_BIN" serve --hostname 127.0.0.1 --port "$OC_PORT" > "$LOGS/oc.log" 2>&1) &
OC_PID=$!
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 -u opencode:splice-token "http://127.0.0.1:$OC_PORT/api/session" || true)
  [ "$code" = "200" ] && break
  sleep 0.3
done
[ "$code" = "200" ] || { echo "opencode 未就绪（$LOGS/oc.log）" >&2; exit 3; }

echo "==> 起 UHP 服务端 :$PORT（driver = opencode）"
"$ROOT/target/release/bin/uhp_opencode.examples.example" "$PORT" "http://127.0.0.1:$OC_PORT" "$WS" "$MODEL" "$PROVIDER" > "$LOGS/uhp.log" 2>&1 &
UHP_PID=$!
trap 'kill $UHP_PID $OC_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/v1/uhp" || true)
  [ "$code" = "200" ] && break
  sleep 0.2
done

echo "==> 跑一个真实任务（要求 opencode 用 shell 工具）"
RESP=$(mktemp)
timeout 180 curl -s -m 180 -H 'Authorization: Bearer dev-token' -H 'UHP-Version: 2026-10-19' \
  -H 'Content-Type: application/json' \
  -d '{"input":"Use the shell tool to run: echo uhp-opencode-42   Then reply with exactly the command output and nothing else.","metadata":{"harness_id":"chrn_opencode"},"stream":false}' \
  "http://127.0.0.1:$PORT/v1/responses" > "$RESP"

python3 - "$RESP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = d.get("output") or []
text = " ".join(c.get("text","") for it in out if isinstance(it,dict) for c in (it.get("content") or []) if isinstance(c,dict))
items = [it.get("type") for it in out if isinstance(it,dict)]
print("status:", d.get("status"))
print("items:", items)
print("usage:", d.get("usage"))
print("text:", text[:200])
assert d.get("status") == "completed", "任务没有 completed"
assert "uhp-opencode-42" in text, "输出里没有探针串"
assert "function_call" in items, "没有记录工具调用"
print("==> real smoke ok")
PY
