// Core.swift — Foundation-only logic: settings, URL parsing, probing,
// discovery, spawning, logging. No AppKit/WebKit imports (testable standalone).
import Foundation
import Darwin

// MARK: - Settings

struct GuiSettings: Codable {
    var port: Int?
    var url: String?
    var cwd: String?
    var dshPath: String?
    var windowWidth: Double?
    var windowHeight: Double?
}

func settingsPath() -> String {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("DSH GUI", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("settings.json").path
}

func loadSettings() -> GuiSettings { loadSettings(from: settingsPath()) }

func loadSettings(from path: String) -> GuiSettings {
    guard let data = FileManager.default.contents(atPath: path),
          let s = try? JSONDecoder().decode(GuiSettings.self, from: data) else { return GuiSettings() }
    return s
}

// MARK: - URL parsing from dsh stdout

/// Extract the port from a `dsh web: http://127.0.0.1:<port> ...` stdout line.
func parseDshUrlPort(_ line: String) -> Int? {
    guard let range = line.range(of: "dsh web: http://127.0.0.1:") else { return nil }
    var digits = ""
    for ch in line[range.upperBound...] {
        if ch.isNumber { digits.append(ch) } else { break }
    }
    return digits.isEmpty ? nil : Int(digits)
}

// MARK: - DSH fingerprint

/// True when an HTTP body is the DSH web app index.
func isDshBody(_ body: String) -> Bool { body.contains("window.__DSH_BOOT__") }

/// Probe one port: GET / and check the DSH fingerprint.
func probePort(_ port: Int, timeout: TimeInterval = 1.5) -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    URLSession.shared.dataTask(with: req) { data, _, _ in
        if let data = data, let body = String(data: data, encoding: .utf8) {
            ok = isDshBody(body)
        }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 1.0)
    return ok
}
