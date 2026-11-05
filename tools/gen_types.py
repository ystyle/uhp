#!/usr/bin/env python3
"""从上游 JSON Schema 生成仓颉类型（uhp.types.generated）。

用法：
  python3 tools/gen_types.py            # 生成
  python3 tools/gen_types.py --check    # 只检查生成物是否最新（CI 用，不一致退出码 1）

设计约束（见 docs/design.md、AGENTS.md）：
  * 输入是 resources/schema/uhp-2026-10-19.schema.json（$defs）。
  * 输出目录 src/types/generated/ 只允许本脚本写；手改会在下次生成时被覆盖。
  * 生成层只依赖 uhp.types.codec，不依赖 transport/server/client。
  * 未知字段一律保真（extras），因为上游 153 个对象节点全部 additionalProperties: true。
  * 手写块（Event 联合、OutputItem 联合、ErrorEnvelope、能力位等）不在生成范围内。
"""
import json
import os
import re
import sys
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "resources", "schema", "uhp-2026-10-19.schema.json")
OUT = os.path.join(ROOT, "src", "types", "generated")

# 由手写层负责、生成器必须跳过的定义
SKIP = {"Capabilities"}

# 依赖的公共类型（手写块，位于 uhp.types.handwritten）
EXTERNAL = set()

# 重命名：与 std 冲突的定义（std.core.Error 是异常基类）
TYPE_RENAMES = {
    "Error": "ErrorObject",
}

# prose 要求「字段必须存在，值可为 null」，而 schema 只标了可空：
# 对这类字段，序列化时 None 也要写成 null（Architecture §6「absent is not empty」）。
# 依据：Tasks §3 的响应字段表（error/usage/store/metadata/previous_response_id 均 required）、
#       Errors §1（param/detail required 且可为 null）。
ALWAYS_EMIT_NULL = {
    "Response": {"error", "incomplete_details", "usage", "store", "metadata", "previous_response_id"},
    "ErrorObject": {"param", "detail"},
}

FAMILIES = [
    ("discovery", ("Discovery", "Implementation", "PluginSchema")),
    ("harness", ("Harness", "McpServer", "Skill", "Model")),
    ("plugin", ("Plugin",)),
    ("task", ("Response", "CreateResponseRequest", "OutputItem", "ContentPart", "Annotation",
              "Usage", "Input", "IncompleteDetails", "Error", "Item")),
    ("session", ("Session", "TurnItem", "File", "Container", "Share")),
    ("environment", ("Environment",)),
    ("memory", ("Memory",)),
]


def pascal(name: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", name)
    out = "".join(p[:1].upper() + p[1:] for p in parts if p)
    return out or "X"


def camel(name: str) -> str:
    p = pascal(name)
    return p[:1].lower() + p[1:]


# 仓颉关键字 / 非法标识符 -> 字段名
RENAMES = {
    "type": "typeName",
    "$schema": "schemaUrl",
    "object": "objectKind",
    "match": "matchValue",
    "func": "funcValue",
    "class": "classValue",
}


def field_name(json_name: str) -> str:
    if json_name in RENAMES:
        return RENAMES[json_name]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", json_name):
        return re.sub(r"[^A-Za-z0-9_]", "_", json_name)
    return json_name


def is_null(tp) -> bool:
    return tp == "null"


def unwrap(tp):
    """返回 (类型表达式, 是否可空)。无法表达时退化为 Raw。"""
    if isinstance(tp, list):
        nonnull = [t for t in tp if not is_null(t)]
        if len(nonnull) == 1 and len(nonnull) != len(tp):
            return unwrap(nonnull[0])[0], True
        if len(nonnull) == 1:
            return unwrap(nonnull[0])[0], False
        return "Raw", False
    if not isinstance(tp, dict):
        return "Raw", False
    if "$ref" in tp:
        name = tp["$ref"].split("/")[-1]
        return TYPE_RENAMES.get(name, name), False
    if "oneOf" in tp or "anyOf" in tp:
        variants = tp.get("oneOf") or tp.get("anyOf")
        nonnull = [v for v in variants if v.get("type") != "null"]
        nullable = len(nonnull) != len(variants)
        if len(nonnull) == 1:
            inner, _ = unwrap(nonnull[0])
            return inner, nullable
        # 多分支联合：生成层不建模（结构以手写层为准）
        return "Raw", nullable
    t = tp.get("type")
    if t == "string":
        return "String", False
    if t == "integer":
        return "Int64", False
    if t == "number":
        return "Float64", False
    if t == "boolean":
        return "Bool", False
    if t == "array":
        inner, _ = unwrap(tp.get("items", {}))
        return "Array<" + inner + ">", False
    if t == "object":
        if tp.get("properties"):
            return "INLINE", False
        return "Raw", False
    if t == "null":
        return "Raw", True
    return "Raw", False


class Gen:
    def __init__(self):
        self.spec = json.load(open(SPEC, encoding="utf-8"))
        self.defs = self.spec["$defs"]
        # 字符串枚举定义：生成层把字段当 String 处理（wire 真实形状），
        # 枚举类型本身也生成，供手写层/调用方做类型安全的解析与展示。
        self.enum_defs = {n for n, d in self.defs.items()
                          if d.get("type") == "string" and d.get("enum")}
        self.inline_classes = []  # (name, schema)
        self.out = {}             # filename -> [lines]
        self.names = set(self.defs)

    # ---------- inline object classes ----------
    def inline_class(self, owner: str, prop: str, schema: dict) -> str:
        name = owner + pascal(prop)
        if name not in [n for n, _ in self.inline_classes]:
            self.inline_classes.append((name, schema))
            self.emit_class(name, schema, "uhp.types.generated")
        return name

    # ---------- 类型解析（带上下文，可解析内联对象） ----------
    def resolve(self, owner: str, prop: str, tp):
        ctype, nullable = unwrap(tp)
        if ctype in self.enum_defs:
            return "String", nullable
        if ctype.startswith("Array<") and ctype[6:-1] in self.enum_defs:
            return "Array<String>", nullable
        if ctype == "INLINE":
            return self.inline_class(owner, prop, tp), nullable
        if ctype == "Array<INLINE>":
            return "Array<" + self.inline_class(owner, prop, tp.get("items", {})) + ">", nullable
        return ctype, nullable

    # ---------- emit ----------
    def emit_class(self, name: str, schema: dict, pkg: str):
        props = schema.get("properties") or {}
        required = set(schema.get("required") or [])
        lines = []
        lines.append("public class " + name + " <: JsonSerializable & JsonDeserializable<" + name + "> {")
        fields = []  # (json_name, cj_name, cj_type, optional, kind)
        for jn, ps in props.items():
            cn = field_name(jn)
            ctype, nullable = self.resolve(name, jn, ps)
            optional = (jn not in required) or nullable
            fields.append((jn, cn, ctype, optional, kind_of(ctype)))
            if optional:
                lines.append("    public var " + cn + ": Option<" + ctype + "> = None")
            else:
                lines.append("    public var " + cn + ": " + ctype + " = " + zero_of(ctype))
        lines.append("    // 未知字段：保真存放，回写时不丢（上游所有对象节点都是开放的）")
        lines.append("    public var extras: Extras = newExtras()")
        lines.append("    public init() {}")
        # toJson
        lines.append("    public func toJson(w: JsonWriter): Unit {")
        lines.append("        w.startObject()")
        for jn, cn, ctype, optional, kind in fields:
            if optional:
                lines.append("        if (let Some(v) <- this." + cn + ") {")
                lines.append("            " + WRITE_SNIPPET(jn, "v", ctype, kind, 12))
                if jn in ALWAYS_EMIT_NULL.get(name, set()):
                    lines.append("        } else {")
                    lines.append('            w.writeName("' + jn + '").writeNullValue()')
                    lines.append("        }")
                else:
                    lines.append("        }")
            else:
                lines.append("        " + WRITE_SNIPPET(jn, "this." + cn, ctype, kind, 8))
        lines.append("        writeExtras(w, this.extras)")
        lines.append("        w.endObject()")
        lines.append("    }")
        # fromJson
        lines.append("    public static func fromJson(r: JsonReader): " + name + " {")
        lines.append("        let res = " + name + "()")
        lines.append("        fromJsonObjectWithExtras(")
        lines.append("            r,")
        lines.append("            [")
        handlers = []
        for jn, cn, ctype, optional, kind in fields:
            if kind == "raw":
                read = "readRaw(r)"
            elif optional:
                read = "r.readValue<Option<" + ctype + ">>()"
            else:
                read = "r.readValue<" + ctype + ">()"
            handlers.append('                ("' + jn + '", { => res.' + cn + " = " + read + " })")
        lines.append(",\n".join(handlers))
        lines.append("            ],")
        lines.append("            res.extras")
        lines.append("        )")
        lines.append("        return res")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        self.out.setdefault(self.bucket(name), []).extend(lines)

    def emit_enum(self, name: str, values):
        lines = []
        lines.append("// 上游字符串枚举；未知值落 Other，不抛错（客户端 MUST 容忍未来新增值）。")
        lines.append("public enum " + name + " {")
        lines.append("    | " + "\n    | ".join(pascal(v) for v in values))
        lines.append("    | Other(String)")
        lines.append("}")
        lines.append("")
        lines.append("public func " + camel(name) + "Parse(s: String): " + name + " {")
        arm = "\n".join('        case "' + v + '" => ' + name + "." + pascal(v) for v in values)
        lines.append("    return match (s) {")
        lines.append(arm)
        lines.append("        case other => " + name + ".Other(other)")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        lines.append("public func " + camel(name) + "Name(v: " + name + "): String {")
        lines.append("    return match (v) {")
        arm2 = "\n".join('        case ' + name + "." + pascal(v) + ' => "' + v + '"' for v in values)
        lines.append(arm2)
        lines.append("        case " + name + ".Other(s) => s")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        self.out.setdefault(self.bucket(name), []).extend(lines)

    def bucket(self, name: str) -> str:
        for fname, prefixes in FAMILIES:
            for p in prefixes:
                if name.startswith(p):
                    return fname + ".cj"
        return "misc.cj"

    # ---------- main ----------
    def run(self):
        for name in sorted(self.defs):
            if name in SKIP:
                continue
            schema = self.defs[name]
            t = schema.get("type")
            cj_name = TYPE_RENAMES.get(name, name)
            if t == "object":
                self.emit_class(cj_name, schema, "uhp.types.generated")
            elif t == "string" and schema.get("enum"):
                self.emit_enum(name, schema["enum"])
            else:
                self.emit_enum(name, schema.get("enum", [])) if schema.get("enum") else None
        # 先把 inline 类提交（它们在 emit_class 内部递归产生），再落盘
        files = {}
        for fname, lines in self.out.items():
            files[fname] = HEADER + "\n".join(lines)
        return files


def kind_of(ctype: str) -> str:
    if ctype == "Raw":
        return "raw"
    if ctype.startswith("Array<"):
        inner = ctype[6:-1]
        return "array_obj" if inner[:1].isupper() and inner not in PRIMS else "array_prim"
    if ctype[:1].isupper() and ctype not in PRIMS:
        return "obj"
    return "prim"


PRIMS = {"String", "Bool", "Int64", "Float64", "Raw"}


def zero_of(ctype: str) -> str:
    if ctype in ("String", "Raw"):
        return '""'
    if ctype == "Bool":
        return "false"
    if ctype in ("Int64", "Float64"):
        return "0"
    if ctype.startswith("Array<"):
        return "[]"
    return ctype + "()"


def WRITE_SNIPPET(jn: str, access: str, ctype: str, kind: str, indent: int) -> str:
    pad = " " * indent
    if kind == "raw":
        return pad + 'w.writeName("' + jn + '").jsonValue(' + access + ")"
    if kind == "prim":
        return pad + 'w.writeName("' + jn + '").writeValue(' + access + ")"
    if kind == "obj":
        return pad + 'w.writeName("' + jn + '"); ' + access + ".toJson(w)"
    if kind == "array_prim":
        return pad + 'w.writeName("' + jn + '").writeValue(' + access + ")"
    inner = ctype[6:-1]
    return (pad + 'w.writeName("' + jn + '"); w.startArray();\n'
            + pad + "for (e in " + access + ") { e.toJson(w) }\n"
            + pad + "w.endArray()")


HEADER = """// 本文件由 tools/gen_types.py 生成，**不要手改**（会被下次生成覆盖）。
// 结构来源：resources/schema/uhp-2026-10-19.schema.json（上游 uhp-2026-10-19.schema.json 原样拷贝）。
package uhp.types.generated

import stdx.encoding.json.stream.{JsonReader, JsonWriter}
import stdx.encoding.json.stream.*
import uhp.types.codec.*
import uhp.types.base.*
"""


def main():
    want_check = "--check" in sys.argv
    files = Gen().run()
    os.makedirs(OUT, exist_ok=True)
    on_disk = set(os.listdir(OUT))
    stale = []
    for fname, content in files.items():
        path = os.path.join(OUT, fname)
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old != content:
            stale.append(fname)
            if not want_check:
                open(path, "w", encoding="utf-8").write(content)
    for extra in on_disk - set(files):
        if not extra.endswith(".cj"):
            continue
        # 只清理本脚本生成的文件：手写/测试文件放在同目录也不会被误删
        p = os.path.join(OUT, extra)
        try:
            head = open(p, encoding="utf-8").read(400)
        except OSError:
            continue
        if "gen_types.py 生成" not in head:
            continue
        stale.append(extra + " (残留)")
        if not want_check:
            os.remove(p)
    if want_check:
        if stale:
            print("生成物不是最新的：", ", ".join(sorted(stale)))
            print("请运行 python3 tools/gen_types.py 后重新提交")
            return 1
        print("生成物最新")
        return 0
    print("生成 " + str(len(files)) + " 个文件到 src/types/generated/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
