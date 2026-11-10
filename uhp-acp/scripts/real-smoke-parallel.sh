#!/usr/bin/env bash
# 真实链路冒烟（并发会话）：opencode acp 当 agent，同一个 ACP 连接里跑两个并发任务。
# 前置：本机有 opencode v2（oc2 目录）且默认模型可用。
# 用法：bash scripts/real-smoke-parallel.sh
set -eo pipefail
ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
OCDIR="$ROOT/../../.uhp-research/oc2"
OC_BIN="$OCDIR/pkg/node_modules/@opencode/cli-linux-x64/bin/opencode"
PORT="8491"
if [ -n "$UHP_PORT" ]; then PORT="$UHP_PORT"; fi
WS="$OCDIR/ws"
if [ -n "$WS_OVERRIDE" ]; then WS="$WS_OVERRIDE"; fi
LOGS="$OCDIR/logs"

if [ ! -x "$OC_BIN" ]; then echo "找不到 opencode v2：$OC_BIN" >&2; exit 2; fi
if [ ! -d "$WS" ]; then echo "找不到工作目录：$WS" >&2; exit 2; fi
mkdir -p "$LOGS"

cd "$ROOT"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cjpm build -j 8

export XDG_CONFIG_HOME="$OCDIR/config" XDG_CACHE_HOME="$OCDIR/cache"
export XDG_DATA_HOME="$OCDIR/data" XDG_STATE_HOME="$OCDIR/state"
export HOME="$OCDIR/home"
export UHP_ACP_SESSION_MODE=parallel
mkdir -p "$HOME"

echo "==> 起 UHP 服务端 :$PORT（driver = ACP Parallel，agent = opencode acp）"
"$ROOT/target/release/bin/uhp_acp.examples.uhp_server" "$PORT" "$WS" "$OC_BIN" acp > "$LOGS/uhp-acp-parallel.log" 2>&1 &
UHP_PID=$!
trap 'kill $UHP_PID 2>/dev/null || true' EXIT
code=""
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/v1/uhp" || true)
  if [ "$code" = "200" ]; then break; fi
  sleep 0.2
done
if [ "$code" != "200" ]; then echo "UHP 服务端未就绪（$LOGS/uhp-acp-parallel.log）" >&2; exit 3; fi

A=$(mktemp); B=$(mktemp)
echo "==> 并发跑两个任务"
START=$(date +%s%N)
curl -s -m 180 -H 'Authorization: Bearer dev-token' -H 'UHP-Version: 2026-10-19' \
  -H 'Content-Type: application/json' \
  -d '{"input":"Write exactly three short sentences about apples, one sentence per line.","metadata":{"harness_id":"chrn_acp"},"stream":false}' \
  "http://127.0.0.1:$PORT/v1/responses" > "$A" &
PA=$!
curl -s -m 180 -H 'Authorization: Bearer dev-token' -H 'UHP-Version: 2026-10-19' \
  -H 'Content-Type: application/json' \
  -d '{"input":"Reply with exactly: PONG-PARALLEL","metadata":{"harness_id":"chrn_acp"},"stream":false}' \
  "http://127.0.0.1:$PORT/v1/responses" > "$B" &
PB=$!
wait $PA $PB
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))

python3 - "$A" "$B" "$ELAPSED_MS" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2])); elapsed = int(sys.argv[3])
def text(d):
    out = d.get("output") or []
    return " ".join(c.get("text","") for it in out if isinstance(it,dict) for c in (it.get("content") or []) if isinstance(c,dict))
ta, tb = text(a), text(b)
print("taskA status:", a.get("status"), "len:", len(ta))
print("taskB status:", b.get("status"), "len:", len(tb))
print("elapsed_ms:", elapsed)
assert a.get("status") == "completed", "任务 A 没有 completed"
assert b.get("status") == "completed", "任务 B 没有 completed"
assert "PONG-PARALLEL" in tb, "任务 B 输出里没有 PONG-PARALLEL"
assert elapsed < 25000, "疑似串行执行（%d ms）" % elapsed
print("==> real smoke parallel ok")
PY
