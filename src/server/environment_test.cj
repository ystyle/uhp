// L2 测试：环境（Environments 章）的引擎行为。
package uhp.server

import std.unittest.*
import std.unittest.testmacro.*
import uhp.types.base.*
import uhp.types.generated.*

func engineWithEnv(): (Engine, String) {
    let h = ScriptedHarness([ScriptStep.Text("ok")], TurnOutcome.Completed(None))
    let e = Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)], cls: ConformanceClass.Full)
    let env = e.createEnvironment(Principal("alice"), "demo env", None, None)
    return (e, env.id)
}

@Test
func environment_starts_empty_with_mount(): Unit {
    let (e, id) = engineWithEnv()
    let env = e.getEnvironment(id)
    @Expect(env.status, "empty")
    @Expect(env.mount.startsWith("/"), true)
    @Expect(env.mount.endsWith("/" + env.slug), true)
    @Expect(env.active.isNone(), true)
}

@Test
func environment_files_round_trip_and_tree(): Unit {
    let (e, id) = engineWithEnv()
    e.putEnvFile(id, "probe/nested/blob.bin", [UInt8(1), UInt8(2), UInt8(0)])
    let got = e.getEnvFile(id, "probe/nested/blob.bin")
    @Expect(got.size, 3)
    let tree = envFilesJson(e.getEnvironment(id))
    @Expect(tree.contains("probe/nested/blob.bin"), true)
    @Expect(tree.contains("probe/nested"), true)
    // 删整棵目录
    e.deleteEnvPath(id, "probe")
    @Expect(envFilesJson(e.getEnvironment(id)).contains("probe"), false)
}

@Test
func environment_escape_paths_are_refused(): Unit {
    let (e, id) = engineWithEnv()
    var code = ""
    try {
        e.putEnvFile(id, "../escape.txt", [UInt8(1)])
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_invalid")
    var code2 = ""
    try {
        e.putEnvFile(id, "/abs.txt", [UInt8(1)])
    } catch (err: EngineError) {
        code2 = err.code
    }
    @Expect(code2, "environment_invalid")
}

@Test
func build_and_activate_version_semantics(): Unit {
    let (e, id) = engineWithEnv()
    e.putEnvFile(id, "data/hello.txt", "v1".toArray())
    let v1 = e.buildEnvironment(id)
    @Expect(v1, 1)
    @Expect(e.getEnvironment(id).active, Some(1))
    // 改源文件不改 active 版本
    e.putEnvFile(id, "data/hello.txt", "v2".toArray())
    @Expect(e.getEnvironment(id).active, Some(1))
    let v2 = e.buildEnvironment(id)
    @Expect(v2, 2)
    @Expect(e.activateEnvVersion(id, 1), 1)
    @Expect(e.getEnvironment(id).active, Some(1))
    // 不存在的版本 -> environment_not_ready
    var code = ""
    try {
        e.activateEnvVersion(id, 99)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_not_ready")
}

@Test
func task_on_unbuilt_environment_is_refused_before_start(): Unit {
    let (e, id) = engineWithEnv()
    var code = ""
    try {
        let _ = e.createTask(Principal("alice"), TaskRequest("hi", environment: Some(id)))
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_not_ready")
    // build 之后可以跑，且响应/会话都记了环境
    e.putEnvFile(id, "data/hello.txt", "hello".toArray())
    let _ = e.buildEnvironment(id)
    let r = e.createTask(Principal("alice"), TaskRequest("hi", environment: Some(id)))
    @Expect(r.response.metadata?.environment, Some(id))
    let meta = r.response.metadata ?? ResponseMetadata()
    let sid = meta.session_id ?? ""
    let sess = e.getSession(Principal("alice"), sid)
    @Expect(sess.environment == Some(id), true)
}

@Test
func harness_pointing_at_missing_environment_is_refused(): Unit {
    let (e, id) = engineWithEnv()
    var code = ""
    try {
        let body = "{\"name\":\"bad\",\"base\":\"scripted\",\"environment\":\"henv_nope\"}"
        let _ = e.createHarness(Principal("alice"), body, None)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_not_found")
}

@Test
func environment_delete_removes_it(): Unit {
    let (e, id) = engineWithEnv()
    e.deleteEnvironment(id)
    var code = ""
    try {
        let _ = e.getEnvironment(id)
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_not_found")
}


func lookupIn(manager: String, spec: String): Option<PackageCheckResult> {
    if (manager != "pip") {
        return None
    }
    if (spec == "pip") {
        return Some(PackageCheckResult(true, Some("26.0.0")))
    }
    return Some(PackageCheckResult(false, None))
}

@Test
func package_check_uses_injected_registry(): Unit {
    let h = ScriptedHarness([ScriptStep.Text("ok")], TurnOutcome.Completed(None))
    let e = Engine([ConfiguredHarness("chrn_1", "n", "scripted", "m", h)],
        cls: ConformanceClass.Full, packageChecker: Some({ m: String, s: String => lookupIn(m, s) }))
    let pip = e.checkEnvironmentPackage("pip", "pip")
    @Expect(pip.contains("\"exists\":true"), true)
    @Expect(pip.contains("26.0.0"), true)
    let unknown = e.checkEnvironmentPackage("pip", "uhp-conformance-no-such-package")
    @Expect(unknown.contains("\"exists\":false"), true)
    var code = ""
    try {
        let _ = e.checkEnvironmentPackage("cargo", "serde")
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "environment_invalid")
}

@Test
func package_check_absent_without_registry(): Unit {
    let (e, _) = engineWithEnv()
    var code = ""
    try {
        let _ = e.checkEnvironmentPackage("pip", "pip")
    } catch (err: EngineError) {
        code = err.code
    }
    @Expect(code, "not_found")
}
