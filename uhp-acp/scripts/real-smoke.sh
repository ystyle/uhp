#!/usr/bin/env bash
# 真实链路冒烟：opencode 的 ACP 模式（opencode acp）当 agent，跑一个 UHP 任务。
#
# 前置：本机有 opencode v2、且默认模型可用（在 opencode 配置里指定 model）。
# 用法：bash scripts/real-smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCDIR="${OCDIR:-$ROOT/../../.uhp-research/oc2}"
OC_BIN="${OC_BIN:-$OCDIR/pkg/node_modules/@opencode/cli-linux-x64/bin/opencode}"
PORT="${UHP_PORT:-8490}"
WS="${WS:-$OCDIR/ws}"
LOGS="$OCDIR/logs"

[ -x "$OC_BIN" ] || { echo "找不到 opencode v2：$OC_BIN" >&2; exit 2; }
mkdir -p "$LOGS"

cd "$ROOT"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cjpm build -j 8

export XDG_CONFIG_HOME="$OCDIR/config" XDG_CACHE_HOME="$OCDIR/cache"
export XDG_DATA_HOME="$OCDIR/data" XDG_STATE_HOME="$OCDIR/state"
export PATH="$(dirname "$OC_BIN"):$PATH"

echo "==> 起 UHP 服务端 :$PORT（driver = ACP，agent = opencode acp）"
"$ROOT/target/release/bin/uhp_acp.examples.uhp_server" "$PORT" "$WS" "$OC_BIN" acp > "$LOGS/uhp-acp.log" 2>&1 &
UHP_PID=$!
trap 'kill $UHP_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/v1/uhp" || true)
  [ "$code" = "200" ] && break
  sleep 0.2
done
[ "$code" = "200" ] || { echo "UHP 服务端未就绪（$LOGS/uhp-acp.log）" >&2; exit 3; }

echo "==> 跑一个真实任务"
RESP=$(mktemp)
timeout 180 curl -s -m 180 -H 'Authorization: Bearer dev-token' -H 'UHP-Version: 2026-10-19' \
  -H 'Content-Type: application/json' \
  -d '{"input":"Reply with exactly: ACP-OK","metadata":{"harness_id":"chrn_acp"},"stream":false}' \
  "http://127.0.0.1:$PORT/v1/responses" > "$RESP"

python3 - "$RESP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = d.get("output") or []
text = " ".join(c.get("text","") for it in out if isinstance(it,dict) for c in (it.get("content") or []) if isinstance(c,dict))
print("status:", d.get("status"))
print("items:", [it.get("type") for it in out if isinstance(it,dict)])
print("text:", text[:200])
assert d.get("status") == "completed", "任务没有 completed"
assert "ACP-OK" in text, "输出里没有 ACP-OK"
print("==> real smoke ok")
PY
