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

// ── parseLsof ────────────────────────────────────────────────────
let lsofSample = """
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node    12454 x 18u  IPv4 0x1 0t0  TCP 127.0.0.1:3080 (LISTEN)
node    12455 x 19u  IPv6 0x2 0t0  TCP [::1]:8080 (LISTEN)
code    12456 x 20u  IPv4 0x3 0t0  TCP *:22 (LISTEN)
"""
let lsofMap = parseLsof(lsofSample)
check("lsof ipv4 loopback", lsofMap[12454] == [3080])
check("lsof ipv6 loopback", lsofMap[12455] == [8080])
check("lsof wildcard", lsofMap[12456] == [22])

// ── dshPids ──────────────────────────────────────────────────────
let psSample = """
12454 /usr/local/bin/node /Users/x/.npm/_npx/abc/node_modules/@deepseek-ai/dsh/lib/bin.js web
12455 /usr/bin/ssh
12456 node /Users/x/.npm/_npx/def/node_modules/@deepseek-ai/dsh/bin.js web --port 0
"""
check("ps filters dsh pids", dshPids(psSample) == [12454, 12456])

// ── discoverPorts 顺序与去重 ─────────────────────────────────────
let settings3 = GuiSettings(port: 8080, url: "http://127.0.0.1:9090", cwd: nil,
                            dshPath: nil, windowWidth: nil, windowHeight: nil)
let ports3 = discoverPorts(settings: settings3, psOut: psSample, lsofOut: lsofSample)
check("discover order url->port->3080->dsh-lsof",
      ports3 == [9090, 8080, 3080, 22]) // 22: pid 12456 (dsh) 监听; 12454 的 3080 已去重; 12455 非 dsh

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
