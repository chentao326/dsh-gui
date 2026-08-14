# DeepSeek Harness GUI

English · [中文](README.zh.md)

<p align="center">
  <img src="assets/AppIcon.svg" width="96" alt="DeepSeek Harness GUI logo" />
</p>

<p align="center">
  <b>Native macOS desktop client for <a href="https://github.com/deepseek-ai/deepseek-harness">DeepSeek Harness</a></b><br>
  Double-click the icon and start using DSH — zero dependencies, no bundled browser.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/dependencies-zero-4d7cfe" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/License-MIT-2EA44F" alt="MIT License">
  <a href="https://github.com/topics/dsh-plugin"><img src="https://img.shields.io/badge/topic-dsh--plugin-4d7cfe" alt="dsh-plugin topic"></a>
</p>

![architecture](assets/architecture.svg)

## Features

- ⚡ **Zero dependencies** — pure Swift over the system WebKit engine; built with only Xcode Command Line Tools. No Node, no Electron, no Chromium (~180 KB binary).
- 🔍 **Automatic server discovery** — settings.json → port 3080 → `lsof` scan of running dsh processes, each verified against the `window.__DSH_BOOT__` fingerprint.
- 🚀 **Self-start when needed** — spawns `dsh web --port N` (N = 0 lets the OS pick a port) and reads the real URL from the readiness line `dsh web: http://127.0.0.1:<port>`.
- 🧹 **Honest lifecycle** — on quit it terminates only the server it started itself (SIGTERM → SIGKILL, by process group); a server that was already running is left untouched.
- 🐋 **Official branding** — the app icon is DeepSeek Harness's own whale, rendered from the shipped favicon.
- ⚙️ **Headless config** — `settings.json` controls port/url, working directory (`cwd`), dsh path and window size.
- 🔁 **Resilient** — 30 s startup timeout, up to 2 automatic reconnects, error page with retry, full log at `~/Library/Logs/dsh-gui.log`.

## Quick start

Requirements: macOS 14+, Xcode Command Line Tools (`xcode-select --install`), and `dsh` on PATH (or set `dshPath`).

```sh
git clone https://github.com/chentao326/dsh-gui.git
cd dsh-gui
bash build.sh          # builds and installs DSH.app to ~/Desktop
```

Or copy the prebuilt bundle from `build/DSH.app` into `/Applications`.

Run the test suite:

```sh
bash build.sh --test   # unit + spawner integration tests
```

Menu shortcuts: `Cmd+R` reload · `Cmd+Shift+O` open in browser · `Cmd+Q` quit.

## Compared with other desktop shells

| | **This project** | [salathleizhang/deepseek-harness-desktop](https://github.com/salathleizhang/deepseek-harness-desktop) | [anywhere-labs/deepseek-harness-desktop](https://github.com/anywhere-labs/deepseek-harness-desktop) |
|---|---|---|---|
| Stack | Swift + system WebKit | Electron (Chromium) | Electron |
| Runtime deps | **none** | bundled Node + Chromium (~100 MB+) | bundled Node + Chromium |
| Installer size | ~180 KB binary | multi-hundred-MB DMG | installer |
| Build | `bash build.sh`, ~30 s, CLT only | pnpm / electron-builder | pnpm / electron-builder |
| Platforms | macOS (arm64; Intel cross-compilable) | macOS + Windows (signed/notarized) | macOS + Windows |
| Server startup | discovery first; spawn only if not found; `--port 0` + stdout parsing | fixed spawn, waits for readiness line | managed service + tray |
| Quit semantics | kills only self-spawned server | owns shutdown & crash-restart | integrated management (tray) |
| Config | `settings.json` (port/url/cwd/dshPath/window) | — | — |

In one sentence: the Electron shells ship a Chromium to distribute installers; this project ships **a few hundred kilobytes of auditable Swift** for people who prefer to build from source.

## Configuration

Optional `~/Library/Application Support/DSH GUI/settings.json`:

```json
{
  "port": 8080,
  "url": "http://127.0.0.1:8080",
  "cwd": "/path/to/project",
  "dshPath": "/path/to/dsh",
  "windowWidth": 1280,
  "windowHeight": 800
}
```

| Key | Effect |
|---|---|
| `port` / `url` | skip discovery and connect directly (`url` wins) |
| `cwd` | working directory of the self-started server (dsh's default filesystem location); defaults to `$HOME` |
| `dshPath` | explicit dsh CLI; default lookup: `which dsh` → newest `~/.npm/_npx/*/.../dsh/lib/bin.js` |
| `windowWidth` / `windowHeight` | initial window size |

## Logs

`~/Library/Logs/dsh-gui.log` — startup, connection and termination events plus the dsh child process output.

## FAQ

**The app says it cannot find `dsh`.**
Install it first: `npm install -g @deepseek-ai/dsh`, or point `dshPath` at your checkout's `lib/bin.js`.

**Port 3080 is taken by something else.**
The app probes 3080 first; if the occupant is not DSH it spawns with `--port 0` and discovers the OS-assigned port from stdout. No manual action needed.

**My server was already running; will the app kill it on quit?**
No. Only a server the app spawned itself is terminated. An external server keeps running (the log records `connected to …` with no termination entry).

**Can it run on Intel Macs?**
The shipped binary is arm64; cross-compile with `swiftc -target x86_64-apple-macos13.0` (SDK supported).

## Documents

- Design spec: `docs/superpowers/specs/2025-08-14-dsh-gui-design.md`
- Implementation plan: `docs/superpowers/plans/2025-08-14-dsh-gui.md`

## License & discoverability

[MIT](LICENSE) © chentao326.

Following the official [DeepSeek Harness README](https://github.com/deepseek-ai/deepseek-harness): add the [`dsh-plugin`](https://github.com/topics/dsh-plugin) topic to your plugin repository for discoverability — this repository is tagged accordingly.
