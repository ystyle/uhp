#!/usr/bin/env python3
"""ACP 能力探针：连一个 ACP agent（stdio，LF 分帧），测
   initialize / session/new / 并发 prompt / session/list / session/close。
用法：python3 scripts/acp-capability-probe.py <command> [args...] --cwd <dir> [--env K=V ...]
"""
import json, os, subprocess, sys, threading, time

def main():
    argv = sys.argv[1:]
    cwd = "/tmp"
    envs = {}
    if "--cwd" in argv:
        i = argv.index("--cwd"); cwd = argv[i+1]; del argv[i:i+2]
    if "--env" in argv:
        i = argv.index("--env"); envs = dict(x.split("=",1) for x in argv[i+1].split(",")); del argv[i:i+2]
    cmd, args = argv[0], argv[1:]
    env = dict(os.environ); env.update(envs); env.setdefault("HOME", cwd)
    t0 = time.time()
    p = subprocess.Popen([cmd]+args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, cwd=cwd, env=env, bufsize=0)
    lock = threading.Lock()
    pending = {}
    timeline = []
    stderr_tail = []
    def reader():
        for raw in p.stdout:
            line = raw.decode("utf-8", "replace").strip()
            if not line: continue
            try: msg = json.loads(line)
            except Exception:
                print("NONJSON:", line[:200]); continue
            with lock:
                if "id" in msg and ("result" in msg or "error" in msg):
                    ev = pending.get(msg["id"])
                    if ev: ev["resp"] = msg; ev["set"].set()
                elif msg.get("method") == "session/update":
                    params = msg.get("params") or {}
                    sid = params.get("sessionId"); upd = (params.get("update") or {}).get("sessionUpdate")
                    timeline.append((time.time()-t0, sid, upd))
                else:
                    timeline.append((time.time()-t0, None, "msg:" + str(msg.get("method"))))
    def stderr_reader():
        for raw in p.stderr:
            s = raw.decode("utf-8","replace").rstrip()
            stderr_tail.append(s)
            if len(stderr_tail) > 40: stderr_tail.pop(0)
    threading.Thread(target=reader, daemon=True).start()
    threading.Thread(target=stderr_reader, daemon=True).start()

    next_id = [0]
    def request(method, params, timeout=30):
        next_id[0] += 1
        rid = next_id[0]
        ev = {"set": threading.Event(), "resp": None}
        with lock: pending[rid] = ev
        payload = {"jsonrpc":"2.0","id":rid,"method":method,"params":params}
        p.stdin.write((json.dumps(payload)+"\n").encode()); p.stdin.flush()
        if not ev["set"].wait(timeout):
            return None
        return ev["resp"]

    def show(label, resp):
        print(f"== {label}: {json.dumps(resp, ensure_ascii=False)[:400] if resp else 'TIMEOUT'}")

    try:
        show("initialize", request("initialize", {"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"0.0.1"}}, 60))
        r1 = request("session/new", {"cwd": cwd, "mcpServers": []}, 60)
        show("session/new#1", r1)
        sid1 = ((r1 or {}).get("result") or {}).get("sessionId")
        r2 = request("session/new", {"cwd": cwd, "mcpServers": []}, 60)
        show("session/new#2", r2)
        sid2 = ((r2 or {}).get("result") or {}).get("sessionId")
        show("session/list", request("session/list", {}, 20))
        if not sid1 or not sid2:
            print("== 无法建两个会话，中止"); return
        tstart = time.time()
        # 并发发两个 prompt（不等待第一个完成）
        f1 = {"resp": None}
        f2 = {"resp": None}
        def run1():
            f1["resp"] = request("session/prompt", {"sessionId": sid1,
                "prompt":[{"type":"text","text":"Write exactly three short sentences about apples, one sentence per line."}]}, 180)
        def run2():
            time.sleep(0.2)
            f2["resp"] = request("session/prompt", {"sessionId": sid2,
                "prompt":[{"type":"text","text":"Reply with exactly: PONG-B"}]}, 180)
        th1 = threading.Thread(target=run1); th2 = threading.Thread(target=run2)
        th1.start(); th2.start(); th1.join(); th2.join()
        el = time.time() - tstart
        show("prompt#1", f1["resp"])
        show("prompt#2", f2["resp"])
        with lock:
            tl = list(timeline)
        def stat(sid):
            ts = [t for (t, s, k) in tl if s == sid]
            return (len(ts), round(min(ts),2) if ts else None, round(max(ts),2) if ts else None)
        s1 = stat(sid1); s2 = stat(sid2)
        print(f"== timeline: total={len(tl)} events; session1 chunks/first/last={s1}; session2={s2}")
        first2 = s2[1]; 
        print(f"== overlap: session2 首帧 {first2}s，session1 末帧 {s1[2]}s => "
              + ("并发执行" if first2 is not None and s1[2] is not None and first2 < s1[2] else "疑似串行/无重叠"))
        print(f"== elapsed both prompts: {el:.1f}s")
        show("session/close#1", request("session/close", {"sessionId": sid1}, 60))
        show("session/close#2", request("session/close", {"sessionId": sid2}, 60))
        show("unknown method probe", request("__probe/nonexistent", {}, 10))
    finally:
        print("== stderr tail:", " | ".join(stderr_tail[-8:])[:800])
        try: p.kill()
        except Exception: pass

main()
