// Spawner integration test: fake dsh -> ServerManager.start -> stdout URL
// parsing -> onUrl -> shutdown kills the process group.
import Foundation
import Darwin

@main
struct SpawnTestMain {
    static var failures = 0

    static func check(_ name: String, _ cond: Bool) {
        print("\(cond ? "PASS" : "FAIL") \(name)")
        if !cond { failures += 1 }
    }

    static func main() {
        let fakeDsh = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "/Volumes/My SSD/deepseekHarness/dsh-gui/Tests/fake-dsh.sh"

        let settings = GuiSettings(port: nil, url: nil, cwd: "/tmp",
                                   dshPath: fakeDsh, windowWidth: nil, windowHeight: nil)
        let mgr = ServerManager()
        var got: URL?
        mgr.onUrl = { got = $0 }
        guard mgr.start(settings: settings, cwd: "/tmp", port: 0) else {
            print("FAIL spawn start returned false")
            exit(1)
        }
        let pid = mgr.process!.processIdentifier

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && got == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        check("onUrl fired with parsed port", got?.port == 39999)

        mgr.shutdown()

        // Reap (Foundation may already have reaped via terminationHandler).
        var status: Int32 = 0
        let wr = waitpid(pid, &status, 0)
        if wr == -1 && errno == ECHILD {
            // already reaped by Foundation -> dead
        } else if wr != pid {
            check("waitpid reaped child (errno \(errno))", false)
        }
        var dead = false
        for _ in 0..<40 { // poll up to 2s for ESRCH
            if kill(pid, 0) == -1 && errno == ESRCH { dead = true; break }
            usleep(50_000)
        }
        check("process dead after shutdown", dead)

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
