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

// MARK: - Process helpers

/// Run a command synchronously (best effort), return stdout, nil on failure.
func runCommand(_ launchPath: String, _ args: [String], timeout: TimeInterval = 5) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let sem = DispatchSemaphore(value: 0)
    var out = ""
    pipe.fileHandleForReading.readabilityHandler = { h in
        let d = h.availableData
        if d.isEmpty {
            sem.signal()
            h.readabilityHandler = nil
        } else {
            out += String(data: d, encoding: .utf8) ?? ""
        }
    }
    _ = sem.wait(timeout: .now() + timeout)
    if p.isRunning { p.terminate() }
    return out
}

// MARK: - Port discovery

/// Parse `lsof -nP -iTCP -sTCP:LISTEN` output into pid -> listening ports.
func parseLsof(_ out: String) -> [Int: Set<Int>] {
    let pattern = #"(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[::1\]|\*):(\d+)"#
    let re = try? NSRegularExpression(pattern: pattern)
    var map: [Int: Set<Int>] = [:]
    for line in out.split(separator: "\n").dropFirst() {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let pid = Int(parts[1]) else { continue }
        let ns = String(line) as NSString
        var ports: Set<Int> = []
        re?.enumerateMatches(in: String(line), range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            if let m = m, m.numberOfRanges > 1,
               let p = Int(ns.substring(with: m.range(at: 1))) { ports.insert(p) }
        }
        if !ports.isEmpty { map[pid, default: []].formUnion(ports) }
    }
    return map
}

/// Pids whose command line mentions dsh (from `ps -axo pid=,command=` output).
func dshPids(_ psOut: String) -> Set<Int> {
    var pids: Set<Int> = []
    for line in psOut.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let pid = Int(parts[0]) else { continue }
        let cmd = parts[1].lowercased()
        if cmd.contains("dsh") || cmd.contains("@deepseek-ai") { pids.insert(pid) }
    }
    return pids
}

/// Candidate ports in priority order: settings.url -> settings.port -> 3080 ->
/// listening ports of dsh processes. Testable: takes pre-captured outputs.
func discoverPorts(settings: GuiSettings, psOut: String?, lsofOut: String?) -> [Int] {
    var candidates: [Int] = []
    var seen: Set<Int> = []
    func add(_ p: Int) { if !seen.contains(p) { seen.insert(p); candidates.append(p) } }
    if let u = settings.url, let port = URL(string: u)?.port { add(port) }
    if let p = settings.port { add(p) }
    add(3080)
    if let psOut, let lsofOut {
        let pids = dshPids(psOut)
        let map = parseLsof(lsofOut)
        for pid in pids {
            for port in map[pid] ?? [] { add(port) }
        }
    }
    return candidates
}

/// Live variant: captures ps + lsof itself.
func discoverPorts(settings: GuiSettings) -> [Int] {
    let psOut = runCommand("/bin/ps", ["-axo", "pid=,command="], timeout: 3)
    let lsofOut = runCommand("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"], timeout: 3)
    return discoverPorts(settings: settings, psOut: psOut, lsofOut: lsofOut)
}

// MARK: - Server command construction

/// Executable + args to boot the dsh web server. A .js path runs under
/// /usr/bin/env node so PATH resolution works on any machine.
func buildServerCommand(cli: String, port: Int) -> (executable: String, args: [String]) {
    if cli.hasSuffix(".js") {
        return ("/usr/bin/env", ["node", cli, "web", "--port", String(port)])
    }
    return (cli, ["web", "--port", String(port)])
}

/// True when anything answers on the port (used to pick --port 0 when 3080 is taken).
func portReachable(_ port: Int, timeout: TimeInterval = 0.8) -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    let sem = DispatchSemaphore(value: 0)
    var reachable = false
    URLSession.shared.dataTask(with: req) { _, resp, _ in
        reachable = resp != nil
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 1.0)
    return reachable
}

/// Locate the dsh CLI: settings.dshPath -> `which dsh` -> newest npx cache copy.
func locateDshCLI(settings: GuiSettings) -> String? {
    if let p = settings.dshPath, FileManager.default.fileExists(atPath: p) { return p }
    if let which = runCommand("/usr/bin/which", ["dsh"], timeout: 3)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !which.isEmpty, FileManager.default.fileExists(atPath: which) { return which }
    let npx = FileManager.default.homeDirectoryForCurrentUser.path + "/.npm/_npx"
    var best: (Date, String)?
    if let entries = try? FileManager.default.contentsOfDirectory(atPath: npx) {
        for e in entries {
            let candidate = npx + "/" + e + "/node_modules/@deepseek-ai/dsh/lib/bin.js"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: candidate) {
                let date = (attrs[.modificationDate] as? Date) ?? .distantPast
                if best == nil || date > best!.0 { best = (date, candidate) }
            }
        }
    }
    return best?.1
}

// MARK: - Logging

final class GuiLog {
    static let shared = GuiLog()
    static let path = NSHomeDirectory() + "/Library/Logs/dsh-gui.log"
    private let handle: FileHandle?
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        FileManager.default.createFile(atPath: GuiLog.path, contents: nil)
        handle = FileHandle(forWritingAtPath: GuiLog.path)
        handle?.seekToEndOfFile()
    }

    func write(_ s: String) {
        let line = "\(GuiLog.iso.string(from: Date())) \(s)\n"
        if let d = line.data(using: .utf8) { handle?.write(d) }
        NSLog("%@", s)
    }
}

// MARK: - Server lifecycle

final class ServerManager {
    private(set) var process: Process?
    private var buffer = ""
    private var stdoutPipe: Pipe?
    private var exited = false
    /// Fired (main queue) with the real URL once `dsh web: http://…` is seen.
    var onUrl: ((URL) -> Void)?
    /// Fired (main queue) when a spawned process exits.
    var onExit: (() -> Void)?

    /// Spawn `dsh web`. Returns false when the CLI is missing.
    @discardableResult
    func start(settings: GuiSettings, cwd: String, port: Int) -> Bool {
        guard let cli = locateDshCLI(settings: settings) else { return false }
        let p = Process()
        let cmd = buildServerCommand(cli: cli, port: port)
        p.executableURL = URL(fileURLWithPath: cmd.executable)
        p.arguments = cmd.args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        var env = ProcessInfo.processInfo.environment
        env["DSH_HOME"] = env["DSH_HOME"] ?? (NSHomeDirectory() + "/.dsh")
        p.environment = env

        stdoutPipe = Pipe()
        p.standardOutput = stdoutPipe
        let errPipe = Pipe()
        p.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if !d.isEmpty { GuiLog.shared.write("[dsh] " + (String(data: d, encoding: .utf8) ?? "")) }
        }

        do {
            try p.run()
        } catch {
            GuiLog.shared.write("spawn failed: \(error)")
            return false
        }
        setpgid(p.processIdentifier, p.processIdentifier)
        process = p

        stdoutPipe?.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let d = h.availableData
            if d.isEmpty { return }
            let s = String(data: d, encoding: .utf8) ?? ""
            GuiLog.shared.write("[dsh] " + s)
            self.buffer += s
            while let nl = self.buffer.firstIndex(of: "\n") {
                let line = String(self.buffer[..<nl])
                self.buffer.removeSubrange(...nl)
                if let port = parseDshUrlPort(line),
                   let url = URL(string: "http://127.0.0.1:\(port)/") {
                    DispatchQueue.main.async { self.onUrl?(url) }
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            self?.exited = true
            DispatchQueue.main.async { self?.onExit?() }
        }
        GuiLog.shared.write("spawned dsh web (pid \(p.processIdentifier), port \(port), cwd \(cwd))")
        return true
    }

    /// Terminate the whole process group: SIGTERM, then SIGKILL after 3s.
    func shutdown() {
        guard let p = process, p.isRunning, !exited else { return }
        GuiLog.shared.write("terminating dsh web (pid \(p.processIdentifier))")
        kill(-p.processIdentifier, SIGTERM)
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { sem.signal() }
        _ = sem.wait(timeout: .now() + 4)
        if p.isRunning { kill(-p.processIdentifier, SIGKILL) }
    }
}

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
