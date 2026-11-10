#!/usr/bin/env bash
# 真实链路冒烟（pi）：pi-acp 当 ACP agent，跑一个 UHP 任务。
#
# 前置：
#   1. 本机装了 pi（npm i -g @earendil-works/pi-coding-agent）与一个 pi 的 ACP 适配器
#   2. pi 有可用模型与凭据：pi auth login，或环境里有 DEEPSEEK_API_KEY
#   3. pi 有默认模型（pi settings 的 defaultProvider/defaultModel）
# 用法：bash scripts/real-smoke-pi.sh
#   PI_ACP_BIN=<适配器可执行>   默认依次找 openma-pi-acp / pi-acp
#   PI_WS=<工作目录> PI_HOME_DIR=<隔离的 HOME>（可选，避免写用户 home）
set -eo pipefail
ROOT="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
WS="$PI_WS"
if [ -z "$WS" ]; then WS="$ROOT/../../.uhp-research/pi-home/ws"; fi
PORT="8492"
if [ -n "$UHP_PORT" ]; then PORT="$UHP_PORT"; fi
LOGS="$ROOT/../../.uhp-research/pi-home/logs"
if [ -n "$PI_HOME_DIR" ]; then mkdir -p "$PI_HOME_DIR/.config"; fi
if [ -z "$DEEPSEEK_API_KEY" ] && [ ! -s "$HOME/.pi/agent/auth.json" ]; then
  echo "pi 未认证：先 pi auth login，或在环境里导出 DEEPSEEK_API_KEY" >&2
  exit 2
fi
if [ -z "$PI_ACP_BIN" ]; then
  if command -v openma-pi-acp >/dev/null; then PI_ACP_BIN=openma-pi-acp; else PI_ACP_BIN=pi-acp; fi
fi
if ! command -v "$PI_ACP_BIN" >/dev/null; then echo "找不到 pi 的 ACP 适配器：$PI_ACP_BIN" >&2; exit 2; fi
mkdir -p "$WS" "$LOGS"

cd "$ROOT"
eval "$(cjvs env zsh)"
eval "$(cjvs stdx-env zsh)"
cjpm build -j 8

# 工具链环境加载完之后再切 HOME：cjvs 自己会往 ~/.config 写东西
if [ -n "$PI_HOME_DIR" ]; then export HOME="$PI_HOME_DIR"; fi

echo "==> 起 UHP 服务端 :$PORT（driver = ACP Serial，agent = $PI_ACP_BIN）"
"$ROOT/target/release/bin/uhp_acp.examples.uhp_server" "$PORT" "$WS" "$PI_ACP_BIN" > "$LOGS/uhp-acp-pi.log" 2>&1 &
UHP_PID=$!
trap 'kill $UHP_PID 2>/dev/null || true' EXIT
code=""
for _ in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/v1/uhp" || true)
  if [ "$code" = "200" ]; then break; fi
  sleep 0.2
done
if [ "$code" != "200" ]; then echo "UHP 服务端未就绪（$LOGS/uhp-acp-pi.log）" >&2; exit 3; fi

RESP=$(mktemp)
echo "==> 跑一个真实任务"
timeout 180 curl -s -m 180 -H 'Authorization: Bearer dev-token' -H 'UHP-Version: 2026-10-19' \
  -H 'Content-Type: application/json' \
  -d '{"input":"Reply with exactly: PI-OK","metadata":{"harness_id":"chrn_acp"},"stream":false}' \
  "http://127.0.0.1:$PORT/v1/responses" > "$RESP"

python3 - "$RESP" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = d.get("output") or []
text = " ".join(c.get("text","") for it in out if isinstance(it,dict) for c in (it.get("content") or []) if isinstance(c,dict))
print("status:", d.get("status"))
print("text:", text[:200])
assert d.get("status") == "completed", "任务没有 completed"
assert "PI-OK" in text, "输出里没有 PI-OK"
print("==> real smoke pi ok")
PY
