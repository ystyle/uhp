// L2 测试：记忆（Memories 章）的引擎行为。
package uhp.server

import std.unittest.*
import std.unittest.testmacro.*
import std.io.*
import stdx.encoding.json.stream.*
import uhp.types.base.*
import uhp.types.generated.*

func engineMem(): Engine {
    let h = ScriptedHarness([ScriptStep.Text("ok")], TurnOutcome.Completed(None))
    return Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)], cls: ConformanceClass.Full)
}

func posOf(text: String, sub: String): Int64 {
    return match (text.indexOf(sub)) {
        case Some(v) => v
        case None => -1
    }
}

func writeJsonBody(text: String): MemoryWrite {
    return parseMemoryWrite(JsonReader(ByteBuffer(text.toArray())))
}

@Test
func memory_tree_ancestors_and_listing(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let rootM = e.createMemory(p, "root", Some("the root"), None, None)
    let child = e.createMemory(p, "accounts", Some("what is known"), Some(rootM.id), None)
    @Expect(child.parentId, Some(rootM.id))
    @Expect(child.ancestors, [rootM.id])
    @Expect(child.provider, rootM.provider)
    let kids = e.memoriesByParent(rootM.id)
    @Expect(kids.size, 1)
    @Expect(kids[0].id, child.id)
    // granted 只有「自己进入」的那种
    let granted = e.grantedMemories()
    @Expect(granted.size, 1)
    @Expect(granted[0].id, rootM.id)
}

@Test
func memory_unknown_reads_404(): Unit {
    let e = engineMem()
    var code = ""
    try {
        let _ = e.getMemory("hmem_nope")
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "memory_not_found")
}

@Test
func record_content_writer_and_trust(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let rec = e.createMemoryRecord(p, m.id, writeJsonBody(
        "{\"type\":\"fact\",\"content\":\"A fact.\",\"attributes\":{\"account\":\"q\"}," +
        "\"written_by\":{\"kind\":\"member\",\"id\":\"someone-else\"}}"))
    let js = memoryRecordJson(rec)
    @Expect(js.contains("[{\"type\":\"text\",\"text\":\"A fact.\"}]"), true)
    @Expect(js.contains("\"trust\":\"untrusted\""), true)
    @Expect(js.contains("someone-else"), false)
    @Expect(js.contains("\"id\":\"alice\""), true)
}

@Test
func record_is_not_visible_through_another_memory(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let a = e.createMemory(p, "a", None, None, None)
    let b = e.createMemory(p, "b", None, None, None)
    let rec = e.createMemoryRecord(p, a.id, writeJsonBody("{\"type\":\"fact\",\"content\":\"x\"}"))
    var code = ""
    try {
        let _ = e.getMemoryRecord(b.id, rec.id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "not_found")
}

@Test
func revision_appends_and_history_marks_superseded(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let rec = e.createMemoryRecord(p, m.id, writeJsonBody("{\"type\":\"fact\",\"content\":\"March\"}"))
    let v2 = e.patchMemoryRecord(p, m.id, rec.id, writeJsonBody("{\"content\":\"April\"}"))
    @Expect(v2.latest().version, 2)
    let hist = memoryHistoryJson(e.getMemoryRecord(m.id, rec.id))
    @Expect(hist.contains("\"status\":\"superseded\""), true)
    @Expect(hist.contains("\"status\":\"active\""), true)
    @Expect(hist.contains("March"), true)
    @Expect(hist.contains("April"), true)
}

@Test
func forget_keeps_trace_and_erase_removes(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let rec = e.createMemoryRecord(p, m.id, writeJsonBody("{\"type\":\"fact\",\"content\":\"x\"}"))
    let f = e.forgetMemoryRecord(m.id, rec.id)
    @Expect(f.status, "forgotten")
    @Expect(e.getMemoryRecord(m.id, rec.id).status, "forgotten")
    @Expect(e.listMemoryRecords(m.id).size, 0)
    let (erased, unreachable) = e.eraseMemoryRecords(m.id, [rec.id])
    @Expect(erased.size, 1)
    @Expect(unreachable.size, 0)
    var code = ""
    try {
        let _ = e.getMemoryRecord(m.id, rec.id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "not_found")
}

@Test
func recall_covers_subtree_but_not_above(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let rootM = e.createMemory(p, "root", None, None, None)
    let child = e.createMemory(p, "child", Some("desc"), Some(rootM.id), None)
    let inChild = e.createMemoryRecord(p, child.id, writeJsonBody("{\"type\":\"fact\",\"content\":\"Quillon renews in March\"}"))
    let inRoot = e.createMemoryRecord(p, rootM.id, writeJsonBody("{\"type\":\"fact\",\"content\":\"Vellacourt is a parent fact\"}"))
    let up = e.recallMemory(rootM.id, "Quillon renews", true, false, 1, 10)
    @Expect(up.contains(inChild.id), true)
    let below = e.recallMemory(child.id, "Vellacourt", true, false, 1, 10)
    @Expect(below.contains(inRoot.id), false)
    let alone = e.recallMemory(rootM.id, "Quillon renews", true, false, 0, 10)
    @Expect(alone.contains(inChild.id), false)
    // 不支持的信号必须显式降级
    let degraded = e.recallMemory(child.id, "Quillon", true, true, 1, 10)
    @Expect(degraded.contains("filters:not_supported"), true)
}

@Test
func prime_returns_standing_newest_first_with_budget(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let rule = e.createMemoryRecord(p, m.id, writeJsonBody("{\"type\":\"procedure\",\"title\":\"Dates\",\"attributes\":{\"standing\":true}}"))
    sleep(Duration.millisecond * 1100)
    let pref = e.createMemoryRecord(p, m.id, writeJsonBody("{\"type\":\"fact\",\"title\":\"Prefers\",\"attributes\":{\"standing\":true}}"))
    let _ = e.createMemoryRecord(p, m.id, writeJsonBody("{\"type\":\"fact\",\"title\":\"Plain fact\"}"))
    let all = e.primeMemory(m.id, 4000)
    @Expect(all.contains(pref.id), true)
    @Expect(all.contains(rule.id), true)
    @Expect(all.contains("Plain fact"), false)
    @Expect(posOf(all, pref.id) < posOf(all, rule.id), true)
    @Expect(all.contains("\"truncated\":false"), true)
    let tight = e.primeMemory(m.id, 1)
    @Expect(tight.contains(pref.id), true)
    @Expect(tight.contains(rule.id), false)
    @Expect(tight.contains("\"truncated\":true"), true)
}

@Test
func move_cycle_refused_and_delete_takes_subtree(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let rootM = e.createMemory(p, "root", None, None, None)
    let child = e.createMemory(p, "child", None, Some(rootM.id), None)
    var code = ""
    try {
        let _ = e.moveMemory(rootM.id, child.id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "memory_invalid")
    e.deleteMemoryTree(rootM.id)
    var gone = ""
    try {
        let _ = e.getMemory(child.id)
    } catch (err: EngineError) {
        gone = err.code
    }
    @Expect(gone, "memory_not_found")
}
