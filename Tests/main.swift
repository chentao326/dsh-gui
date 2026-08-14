import Foundation

var failures = 0
func check(_ name: String, _ cond: Bool) {
    print("\(cond ? "PASS" : "FAIL") \(name)")
    if !cond { failures += 1 }
}

// ── parseDshUrlPort ──────────────────────────────────────────────
check("parse basic url", parseDshUrlPort("dsh web: http://127.0.0.1:4321") == 4321)
check("parse with LAN suffix",
      parseDshUrlPort("dsh web: http://127.0.0.1:4321 (LAN: http://192.168.1.2:4321)") == 4321)
check("parse returns nil on junk", parseDshUrlPort("hello world") == nil)
check("parse returns nil when port empty", parseDshUrlPort("dsh web: http://127.0.0.1:") == nil)

// ── isDshBody ────────────────────────────────────────────────────
check("fingerprint detected", isDshBody("<!doctype html><script>window.__DSH_BOOT__ = {}</script>"))
check("non-dsh page rejected", !isDshBody("<html>hello</html>"))

// ── loadSettings ─────────────────────────────────────────────────
let tmp = "/Volumes/My SSD/deepseekHarness/dsh-gui/build/tmp-settings.json"
try? FileManager.default.removeItem(atPath: tmp)
let empty = loadSettings(from: tmp)
check("missing file -> defaults", empty.port == nil && empty.url == nil && empty.cwd == nil)
let bad = "/Volumes/My SSD/deepseekHarness/dsh-gui/build/bad-settings.json"
try? "not json{{{".write(toFile: bad, atomically: false, encoding: .utf8)
let fallback = loadSettings(from: bad)
check("invalid json -> defaults", fallback.port == nil)
let good = "/Volumes/My SSD/deepseekHarness/dsh-gui/build/good-settings.json"
try? #"{"port": 8080, "cwd": "/tmp", "windowWidth": 1440}"#.write(toFile: good, atomically: false, encoding: .utf8)
let parsed = loadSettings(from: good)
check("valid json parsed", parsed.port == 8080 && parsed.cwd == "/tmp" && parsed.windowWidth == 1440)

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
