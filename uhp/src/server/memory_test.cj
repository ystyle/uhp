// L2 测试：记忆（Memories 章）的引擎行为。
package uhp.server

import std.collection.ArrayList
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

func closedOf(e: Engine, rid: String): Array<String> {
    let (c, _) = e.writeExtrasOf(rid)
    return c
}

func conflictsOf(e: Engine, rid: String): Array<String> {
    let (_, x) = e.writeExtrasOf(rid)
    return x
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


func entityBody(title: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("type").writeValue("entity")
    w.writeName("title").writeValue(title)
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func cityFactBody(city: String, t: String, subjectId: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("type").writeValue("fact")
    w.writeName("title").writeValue("lives in " + city)
    w.writeName("references")
    w.startArray()
    w.startObject()
    w.writeName("rel").writeValue("subject")
    w.writeName("record_id").writeValue(subjectId)
    w.endObject()
    w.endArray()
    w.writeName("attributes")
    w.startObject()
    w.writeName("predicate").writeValue("home_city")
    w.writeName("value").writeValue(city)
    w.writeName("holds").writeValue("one")
    w.writeName("stated_at").writeValue(t)
    w.endObject()
    w.writeName("time")
    w.startObject()
    w.writeName("valid_from").writeValue(t)
    w.endObject()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

func edgeFactBody(title: String, subjectId: String, objectId: String): String {
    let out = ByteBuffer()
    let w = JsonWriter(out)
    w.startObject()
    w.writeName("type").writeValue("fact")
    w.writeName("title").writeValue(title)
    w.writeName("references")
    w.startArray()
    w.startObject()
    w.writeName("rel").writeValue("subject")
    w.writeName("record_id").writeValue(subjectId)
    w.endObject()
    w.startObject()
    w.writeName("rel").writeValue("object")
    w.writeName("record_id").writeValue(objectId)
    w.endObject()
    w.endArray()
    w.endObject()
    w.flush()
    return String.fromUtf8(out.bytes())
}

@Test
func temporal_fact_closes_and_conflicts(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let ent = e.createMemoryRecord(p, m.id, writeJsonBody(entityBody("Corvel")))
    let t0 = "2023-01-01T00:00:00Z"
    let t1 = "2024-01-01T00:00:00Z"
    let t15 = "2024-03-01T00:00:00Z"
    let t2 = "2024-06-01T00:00:00Z"
    let lis = e.createMemoryRecord(p, m.id, writeJsonBody(cityFactBody("Lisbon", t1, ent.id)))
    @Expect(closedOf(e, lis.id).size, 0)
    let por = e.createMemoryRecord(p, m.id, writeJsonBody(cityFactBody("Porto", t2, ent.id)))
    @Expect(closedOf(e, por.id), [lis.id])
    @Expect((timeField(e.getMemoryRecord(m.id, lis.id).latest().timeJson, "valid_to") ?? ""), t2)
    let braga = e.createMemoryRecord(p, m.id, writeJsonBody(cityFactBody("Braga", t2, ent.id)))
    @Expect(closedOf(e, braga.id).size, 0)
    @Expect(conflictsOf(e, braga.id), [por.id])
    let faro = e.createMemoryRecord(p, m.id, writeJsonBody(cityFactBody("Faro", t0, ent.id)))
    @Expect((timeField(e.getMemoryRecord(m.id, faro.id).latest().timeJson, "valid_to") ?? ""), t1)
    let coimbra = e.createMemoryRecord(p, m.id, writeJsonBody(cityFactBody("Coimbra", t15, ent.id)))
    @Expect(closedOf(e, coimbra.id), [lis.id])
    @Expect((timeField(e.getMemoryRecord(m.id, coimbra.id).latest().timeJson, "valid_to") ?? ""), t2)
    @Expect((timeField(e.getMemoryRecord(m.id, lis.id).latest().timeJson, "valid_to") ?? ""), t15)
    let hist = e.getMemoryRecord(m.id, lis.id).versions
    @Expect(timeField(hist[0].timeJson, "valid_to").isNone(), true)
    @Expect(e.getMemoryRecord(m.id, lis.id).latest().writtenByJson.contains("provider"), true)
}

func graphNodeIds(json: String): Array<String> {
    let out = ArrayList<String>()
    try {
        let r = JsonReader(ByteBuffer(json.toArray()))
        r.startObject()
        while (true) {
            let name = match (r.peek()) {
                case Some(JsonToken.EndObject) => break
                case Some(JsonToken.Name) => r.readName()
                case _ => break
            }
            if (name != "nodes") {
                r.skip()
                continue
            }
            r.startArray()
            while (true) {
                match (r.peek()) {
                    case Some(JsonToken.EndArray) => break
                    case Some(JsonToken.BeginObject) =>
                        let node = String.fromUtf8(r.readValueBytes())
                        match (tryParseJsonObject(node)) {
                            case Some(o) => match (o.raw("record")) {
                                case Some(rec) => match (tryParseJsonObject(rec)) {
                                    case Some(ro) => match (ro.str("id")) {
                                        case Some(id) => out.add(id)
                                        case None => ()
                                    }
                                    case None => ()
                                }
                                case None => ()
                            }
                            case None => ()
                        }
                    case _ => r.skip()
                }
            }
            r.endArray()
        }
        r.endObject()
    } catch (e: Exception) {
        ()
    }
    return out.toArray()
}

@Test
func graph_reaches_two_hops_through_fact(): Unit {
    let e = engineMem()
    let p = Principal("alice")
    let m = e.createMemory(p, "m", None, None, None)
    let a = e.createMemoryRecord(p, m.id, writeJsonBody(entityBody("Ines")))
    let b = e.createMemoryRecord(p, m.id, writeJsonBody(entityBody("Harlow")))
    let f = e.createMemoryRecord(p, m.id, writeJsonBody(edgeFactBody("works_at", a.id, b.id)))
    let two = graphNodeIds(e.memoryGraph(m.id, a.id, 2))
    @Expect(two.contains(f.id), true)
    @Expect(two.contains(b.id), true)
    let one = graphNodeIds(e.memoryGraph(m.id, a.id, 1))
    @Expect(one.contains(f.id), true)
    @Expect(one.contains(b.id), false)
}
