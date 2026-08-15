# DSH GUI 桌面应用设计文档

日期：2025-08-14
状态：已获用户批准（v2，含动态端口 + 官方鲸鱼图标）

## 1. 目标

DeepSeek Harness 目前只有 Web UI（浏览器访问 `http://127.0.0.1:3080`）。本项目的目标是提供一个 **macOS 原生桌面 GUI**：桌面一个图标，双击打开即用——自带独立窗口（内置浏览器内核），自动管理 DSH 后台服务生命周期。

用户已确认的关键决策：

- **形态**：独立桌面窗口 App（WKWebView 内嵌，不用 Electron）
- **服务生命周期**：App 退出时关闭**它自己启动**的服务；若服务在 App 启动前已在运行，退出时不干预
- **安装位置**：桌面（`~/Desktop/DSH.app`）
- **端口**：不假设 3080，动态发现/自管
- **图标**：DSH 官方黑鲸鱼（`dsh-web-frontend/dist/favicon.svg`）

## 2. 环境事实（已验证）

| 项 | 值 |
|---|---|
| 操作系统 | macOS 15.7.5 (arm64) |
| 工具链 | `/usr/bin/swiftc`（Xcode CommandLineTools，Swift 6.0.3） |
| 编译器注意 | 默认 `-sdk` 指向的 SDK 与编译器小版本不匹配，必须显式 `-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk` 编译；且 clang 模块缓存必须重定向到工作区（`-module-cache-path` / `-Xcc -fmodules-cache-path=`），否则沙箱/权限报错 |
| DSH CLI | `dsh web`（npx 缓存：`~/.npm/_npx/<hash>/node_modules/@deepseek-ai/dsh/lib/bin.js`），支持 `--host`、`--port`、`--trusted-host`；`--port 0` 让系统分配空闲端口 |
| 服务地址日志 | 服务启动后向 stdout 打印 `dsh web: http://127.0.0.1:<port>`，可用于解析随机端口 |
| 默认端口 | 3080，绑定 127.0.0.1 |
| DSH_HOME | `~/.dsh`（App 启动子进程时须继承） |
| 鲸鱼素材 | `dsh-web-frontend/dist/favicon.svg`（黑鲸鱼，黑色 #000 填充，深色模式变白） |
| SVG→PNG 渲染 | Swift + AppKit `NSImage(contentsOf:)` + `NSBitmapImageRep` 已验证可行 |

## 2b. 官方开发文档调研结论（2025-08-14，deepseek-harness.github.io）

来源：`develop/basic/`（第一个插件）、`reference/`（架构）、`reference/subsystems/web-server`（HTTP 服务器）、`guide/quickstart`（Web UI 使用）。

| 结论 | 对设计的影响 |
|---|---|
| **服务识别指纹**：首页响应含 `<script>window.__DSH_BOOT__ = {...}`（已对运行中实例验证）；SPA 回退使任意未匹配路径都返回 200 + index.html | 探测逻辑：`GET /` → HTTP 200 且含 `__DSH_BOOT__` 即确认为 DSH 服务 |
| **服务器自身不打印任何输出**："URL 行归 shell 所有"——CLI 打印 `dsh web: http://127.0.0.1:<port>`（可能带 ` (LAN: …)` 后缀）；quickstart 也说明"命令会打印其访问地址" | stdout 解析是官方机制：正则 `dsh web: http://127\.0\.0\.1:(\d+)` |
| **监听失败即启动失败**：EADDRINUSE 使初始化被拒绝，进程报告失败 fiber | 自起前必须已探测 3080；被非 DSH 进程占用 → 立即 `--port 0`，不必等子进程报错 |
| **host 仅接受 127.0.0.1 / 0.0.0.0**；无 TLS/认证/origin 策略，非回环绑定=向网络暴露 RCE（文档明确警告） | GUI 永远只连 `127.0.0.1`，绝不传 `--host 0.0.0.0` |
| **信任域**：`trustedHosts = [...lanAddresses, ...--trusted-host 值]`，默认含 127.0.0.1 | 从 `http://127.0.0.1:<port>` 加载即默认受信任，无需额外参数 |
| **cwd 语义**：`dsh` 进程把调用目录作为默认文件系统位置；新 Web UI 在添加工作区前不选中任何工作区 | settings.json 支持 `"cwd"`（默认 `$HOME`），子进程以其为工作目录——用户可预设项目目录，实现"打开即用" |
| **官方 Electron 壳**：从 `file://` 加载已构建文件、经 IPC 桥接 fetch，不使用 HTTP 服务器 | 架构决策记录：本项目**不采用**该路线——WKWebView 无法低成本复刻 IPC 桥；HTTP 是文档认定的浏览器托管一等路径，且本产品服务器即本体 |
| **`dsh web` 不自动打开浏览器**，仅打印 URL | 无需禁开浏览器逻辑 |
| **模型/API 密钥配置**在 Web UI 设置页完成，无需重启 | GUI 无相关职责 |

## 3. 架构

单文件 Swift 应用（`main.swift`），AppKit + WebKit，`swiftc` 直接编译为 `.app` 包，零外部依赖。

```
┌─────────────────────────────────────────────┐
│ DSH.app (Swift/AppKit/WKWebView)            │
│                                             │
│  ┌───────────┐    ┌──────────────────────┐  │
│  │ 启动编排器 │───▶│ WKWebView 窗口        │  │
│  │ 发现/拉起/ │    │ 加载 http://127.0.0.1 │  │
│  │ 探活/回收  │    │ :<port>              │  │
│  └─────┬─────┘    └──────────────────────┘  │
│        │                                     │
│        ▼                                     │
│  ┌───────────┐    ┌──────────────────────┐  │
│  │ 子进程管理  │───▶│ dsh web --port N     │  │
│  │ (posix_spawn│   │ stdout 解析真实端口   │  │
│  │  / NSTask) │    │ 日志 → ~/Library/    │  │
│  └───────────┘    │  Logs/dsh-gui.log     │  │
└─────────────────────────────────────────────┘
```

### 组件职责

1. **端口发现器（discover）**：在启动窗口前定位已运行的 DSH 服务
2. **服务启动器（spawner）**：发现失败时拉起 `dsh web` 子进程，解析 stdout 得真实 URL
3. **探活器（health）**：HTTP GET 探测某 URL 是否为 DSH 服务（响应含 `__DSH_BOOT__` 特征或 favicon 路径）
4. **窗口/控制器（app）**：AppKit 生命周期、WKWebView、菜单、退出逻辑
5. **图标生成（build 期）**：Swift 渲染 SVG → 合成白底 → sips 缩放 → iconutil 打包 .icns

## 4. 端口发现策略（按顺序）

1. **settings.json 覆盖**：读 `~/Library/Application Support/DSH GUI/settings.json`，若含 `"port"`（或 `"url"`）则直接探测该地址（高级用户/特殊部署）
2. **默认端口 3080**：`GET /` 探测，200 且响应含 `window.__DSH_BOOT__` 即确认
3. **lsof 扫描**：执行 `lsof -nP -iTCP -sTCP:LISTEN`，过滤命令行含 `dsh`/`@deepseek-ai` 的 node 进程，取其监听端口，逐个按上述指纹探测确认（同一进程可能有多个监听端口，如 3080 + 开发 HMR 端口，靠指纹过滤）
4. **全部失败 → 自起服务**：
   - 先试 `--port 3080`；若该端口已被非 DSH 进程占用，改用 `--port 0` 由系统分配（文档确认 EADDRINUSE 会导致启动失败，故必须预先探测）
   - 从子进程 stdout 正则解析 `dsh web: http://127\.0\.0\.1:(\d+)`（忽略 ` (LAN: …)` 后缀）
   - 解析失败时轮询 lsof 发现（限时，如 20s）

## 5. 服务生命周期

- **App 启动**：先发现 → 找到即用（标记 `external=true`）；找不到则拉起（`external=false`）
- **App 退出**（Cmd+Q / 菜单退出 / 窗口关闭）：
  - `external=false`：SIGTERM 子进程，等 3s 后仍未退出再 SIGKILL（node 收到 SIGTERM 默认退出并释放端口）
  - `external=true`：不干预
- **崩溃兜底**：App 异常退出时子进程可能成为孤儿——子进程启动时放入独立进程组，App 退出时 `kill(-pgid)` 整组回收，下次启动按发现流程复用/接管

## 6. 窗口与 UI

- 窗口：1280×800，最小 800×600，标题 "DeepSeek Harness"
- 启动期间：窗口内显示本地进度页（"正在连接 DSH…"），内嵌在 WKWebView 的 HTML 里轮询探活，服务就绪后 `load(URL)` 切到真实 GUI；失败超过 30s 显示错误页（含日志路径与"重试"按钮）
- 菜单栏：
  - App 菜单：关于、退出（Cmd+Q）
  - 视图菜单：重新加载（Cmd+R）、在浏览器中打开（Cmd+Shift+O，`NSWorkspace.open`）
  - 窗口菜单：最小化、缩放（标准）
- 权限：App 沙盒**不启用**（需要 spawn 子进程、lsof、写日志），Info.plist 无 sandbox entitlement；安全上仅连接 127.0.0.1
- Info.plist 加 `NSAppTransportSecurity → NSAllowsLocalNetworking = true`（WKWebView 加载本地 HTTP 的 ATS 豁免，杜绝隐患）
- `trustedHosts`：加载来源为 `http://127.0.0.1:<port>`，属 DSH 默认信任域（文档确认），无需额外参数

## 6b. settings.json（高级配置）

路径：`~/Library/Application Support/DSH GUI/settings.json`（不存在即全部默认）：

```json
{
  "port": 3080,        // 可选：跳过发现，直接探测该端口
  "url": "http://127.0.0.1:8080",  // 可选：完全指定地址（优先于 port）
  "cwd": "/path/to/project",       // 可选：自起服务的工作目录（dsh 默认文件系统位置）；默认 $HOME
  "dshPath": "/path/to/dsh",       // 可选：显式指定 dsh CLI；默认自动定位
  "windowWidth": 1280, "windowHeight": 800  // 可选：窗口尺寸
}
```

## 7. 图标（构建期生成）

1. 复制官方 `favicon.svg`，注入白色圆角矩形背景（合成"白底黑鲸鱼"）
2. `swiftc` 编译的 `svg2png` 工具渲染 1024×1024 PNG
3. `sips -z` 生成 iconset 全套尺寸（16/32/128/256/512 及 @2x）
4. `iconutil -c icns` 打包 `AppIcon.icns`，写入 `Contents/Resources/`

## 8. 构建与安装（build.sh）

产物布局（源码存于 `dsh-gui/`）：

```
dsh-gui/
  main.swift        # App 全部逻辑
  build.sh          # 一键构建：编译 → 图标 → 打包 .app → 安装到桌面
  assets/
    AppIcon.svg     # 白底鲸鱼合成 SVG
  scripts/
    svg2png.swift   # SVG→PNG 渲染工具
```

`build.sh` 步骤：

1. 生成图标（svg2png + sips + iconutil）
2. `swiftc -sdk <MacOSX15.2.sdk> -module-cache-path <工作区> ... main.swift -o DSH`（AppKit/WebKit 链接）
3. 组装 `DSH.app/Contents/{MacOS/DSH, Resources/AppIcon.icns, Info.plist}`
4. 复制到 `~/Desktop/DSH.app`（旧版本先删除）
5. 打印完成提示

Info.plist 关键项：`CFBundleIdentifier=com.deepseek.dsh-gui`、`CFBundleName=DeepSeek Harness`、`LSMinimumSystemVersion=13.0`、`NSHighResolutionCapable`、`CFBundleIconFile=AppIcon`、`LSUIElement=false`。

DSH 服务命令定位（App 运行时）：settings.json `dshPath`（显式）→ `which dsh` → 扫描 `~/.npm/_npx/*/node_modules/@deepseek-ai/dsh/lib/bin.js`（取最新）→ 仍未找到则在错误页给出安装指引。启动命令：`<node> <bin.js> web --port <port>`，环境继承 `DSH_HOME`、`PATH`、`HOME`，工作目录取 settings `cwd`（默认 `$HOME`）。

## 9. 错误处理

| 场景 | 处理 |
|---|---|
| 编译失败 | build.sh 打印 swiftc 错误并退出非零 |
| 找不到 node/dsh | 错误页显示指引（安装 dsh 后重试） |
| 子进程启动后 30s 内无地址日志 | 杀掉子进程，错误页显示日志路径 |
| 服务就绪后中途挂掉 | 若子进程是 App 自起的：自动走"发现→自起"重连（最多 2 次，间隔 3s）；重连失败则窗口显示错误页（含日志路径与"重试"按钮）。若为外部服务：仅显示连接错误 + 菜单"重新加载" |
| 端口被非 DSH 占用 | 探测特征不符 → 视为未发现 → 换 `--port 0` |

## 10. 测试

- 单元（编译期断言 + 少量 Swift 测试目标，随 build.sh `--test` 开关）：
  - stdout 解析函数：`dsh web: http://127.0.0.1:4321` → 4321
  - settings.json 解析（缺失/非法/合法）
- 手动验收（build.sh 后执行清单）：
  1. 桌面出现 DSH.app，图标为白底黑鲸鱼
  2. 双击打开，服务未运行时自动拉起并加载 GUI ≤15s
  3. 服务已运行（不同端口）时，App 直接连上且退出后服务仍在
  4. 3080 被非 DSH 进程占用时，App 用 `--port 0` 随机端口正常起服务
  5. settings.json 的 `port`/`cwd` 生效（预设工作目录后 App 内会话输入框可用）
  6. 退出 App 后其自起服务消失（端口释放）
  7. Cmd+R 重载、Cmd+Shift+O 浏览器打开生效
  8. 日志写入 `~/Library/Logs/dsh-gui.log`

## 11. 范围外（YAGNI）

- 不做 Windows/Linux 版（未来可加 Electron 壳，本期不涉及）
- 不做自动更新、偏好设置面板（settings.json 已覆盖高级场景）
- 不做系统托盘常驻
