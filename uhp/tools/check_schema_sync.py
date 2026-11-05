#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验 resources/schema 里 vendored 的 UHP 上游制品。

为什么需要它：SDK 把 schema 当「随包发布的资源」而不是「参考文档」，
所以必须能证明「本仓实现的是 2026-10-19 那份不可变制品」。三条断言
（设计 §4.6 / 调研报告 §1.3）：

  1) 两个制品的 sha256 与 resources/schema/manifest.json 记录一致；
  2) schema.json 的 92 个 $defs 名字全部出现在 openapi.yaml 文本里
     （上游 build.py 只搬 components.schemas，两个文件本应同源）；
  3) schema.json 的 Event.type.examples 恰好 18 条（流式事件词汇表）。

任何一条不满足就打印差异并以 1 退出。**本脚本只读**：不一致时报告，
绝不修改 resources/schema/ 里的内容——上游制品不可变，改了就再也证不了版本。

用法：
    python3 tools/check_schema_sync.py

只依赖标准库；CI 必跑（在 scripts/test.sh 之外单独跑，见 AGENTS.md）。
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "resources" / "schema"
MANIFEST_PATH = SCHEMA_DIR / "manifest.json"

PROTOCOL_VERSION = "2026-10-19"
OPENAPI_NAME = "uhp-2026-10-19.openapi.yaml"
SCHEMA_NAME = "uhp-2026-10-19.schema.json"
EXPECTED_DEFS = 92
EXPECTED_EVENT_EXAMPLES = 18


def rel(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def sha256_of(path):
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(errors, message):
    errors.append(message)


def load_manifest(errors):
    if not MANIFEST_PATH.is_file():
        collect(errors, "缺少清单：" + rel(MANIFEST_PATH))
        return None
    try:
        return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        collect(errors, "清单不可读：" + rel(MANIFEST_PATH) + "（" + str(exc) + "）")
        return None


def check_artifacts(manifest, errors, notes):
    if manifest.get("protocol_version") != PROTOCOL_VERSION:
        collect(
            errors,
            "manifest.protocol_version 期望 " + PROTOCOL_VERSION
            + "，实际 " + repr(manifest.get("protocol_version")),
        )
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        collect(errors, "manifest.artifacts 缺失或不是数组")
        return {}
    by_name = {}
    for entry in artifacts:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            collect(errors, "manifest.artifacts 存在非法条目：" + repr(entry)[:120])
            continue
        by_name[entry["path"]] = entry
    expected = {OPENAPI_NAME, SCHEMA_NAME}
    if set(by_name) != expected:
        collect(
            errors,
            "manifest.artifacts 路径集合应与 {" + ", ".join(sorted(expected))
            + "} 完全一致，实际 {" + ", ".join(sorted(by_name)) + "}",
        )
    # 逐个校验文件存在 / 大小 / 行数 / sha256
    for name in sorted(expected & set(by_name)):
        entry = by_name[name]
        path = SCHEMA_DIR / name
        if not path.is_file():
            collect(errors, "缺少制品：" + rel(path))
            continue
        if isinstance(entry.get("bytes"), int) and path.stat().st_size != entry["bytes"]:
            collect(
                errors,
                rel(path) + " 字节数不一致：manifest=" + str(entry["bytes"])
                + " 实际=" + str(path.stat().st_size),
            )
        if isinstance(entry.get("lines"), int):
            actual_lines = len(path.read_text(encoding="utf-8").splitlines())
            if actual_lines != entry["lines"]:
                collect(
                    errors,
                    rel(path) + " 行数不一致：manifest=" + str(entry["lines"])
                    + " 实际=" + str(actual_lines),
                )
        expected_sha = entry.get("sha256")
        actual_sha = sha256_of(path)
        if expected_sha != actual_sha:
            collect(
                errors,
                rel(path) + " sha256 不一致：manifest=" + str(expected_sha)
                + " 实际=" + actual_sha,
            )
        else:
            notes.append(rel(path) + " sha256=" + actual_sha[:12] + "… bytes="
                         + str(path.stat().st_size))
    return by_name


def check_schema_vs_openapi(errors, notes):
    schema_path = SCHEMA_DIR / SCHEMA_NAME
    openapi_path = SCHEMA_DIR / OPENAPI_NAME
    if not schema_path.is_file() or not openapi_path.is_file():
        collect(errors, "无法做 schema/openapi 交叉校验：制品缺失")
        return
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        collect(errors, rel(schema_path) + " 不是合法 JSON：" + str(exc))
        return
    openapi_text = openapi_path.read_text(encoding="utf-8")

    defs = schema.get("$defs")
    if not isinstance(defs, dict):
        collect(errors, rel(schema_path) + " 缺少 $defs 对象")
        return
    if len(defs) != EXPECTED_DEFS:
        collect(
            errors,
            "$defs 数量期望 " + str(EXPECTED_DEFS) + "，实际 " + str(len(defs)),
        )
    missing = sorted(name for name in defs if name not in openapi_text)
    if missing:
        preview = ", ".join(missing[:20]) + (" …" if len(missing) > 20 else "")
        collect(
            errors,
            "有 " + str(len(missing)) + " 个 $defs 名字未出现在 openapi.yaml："
            + preview,
        )
    else:
        ref_marked = sum(1 for name in defs if "#/components/schemas/" + name in openapi_text)
        notes.append("$defs=" + str(len(defs)) + " 全部出现在 openapi.yaml（其中 "
                     + str(ref_marked) + " 个以 $ref 形式被引用）")

    event = defs.get("Event")
    examples = None
    if isinstance(event, dict):
        type_prop = event.get("properties")
        if isinstance(type_prop, dict):
            type_node = type_prop.get("type")
            if isinstance(type_node, dict):
                examples = type_node.get("examples")
    if not isinstance(examples, list):
        collect(errors, "Event.properties.type.examples 缺失或不是数组（流式事件词汇表）")
    elif len(examples) != EXPECTED_EVENT_EXAMPLES:
        collect(
            errors,
            "Event.type.examples 期望 " + str(EXPECTED_EVENT_EXAMPLES)
            + " 条，实际 " + str(len(examples)),
        )
    else:
        notes.append("Event.type.examples=" + str(len(examples)))


def main():
    errors = []
    notes = []
    manifest = load_manifest(errors)
    if manifest is not None:
        check_artifacts(manifest, errors, notes)
        check_schema_vs_openapi(errors, notes)

    if errors:
        print("[FAIL] check_schema_sync 发现 " + str(len(errors)) + " 条不一致：")
        for item in errors:
            print("  - " + item)
        print("提示：本脚本只读。不要手改 resources/schema/ 的内容；")
        print("      若上游发布新版本，先更新制品与 manifest 的 sha256，再改生成器。")
        return 1

    print("[ok] check_schema_sync：UHP 制品与 manifest 一致（protocol_version="
          + PROTOCOL_VERSION + "）")
    for item in notes:
        print("  - " + item)
    print("  - manifest: " + rel(MANIFEST_PATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
