# DSH GUI — DeepSeek Harness 桌面客户端

macOS 原生桌面 App：双击图标即打开 DeepSeek Harness Web UI（独立窗口，内置 WebKit），自动发现或启动 DSH 服务，退出时仅关闭自己启动的服务。

## 与其他桌面端的区别

| 维度 | **本项目 DSH GUI** | [salathleizhang/deepseek-harness-desktop](https://github.com/salathleizhang/deepseek-harness-desktop) | [anywhere-labs/deepseek-harness-desktop](https://github.com/anywhere-labs/deepseek-harness-desktop) |
|---|---|---|---|
| 技术栈 | 纯 Swift + 系统 WebKit（WKWebView） | Electron（Chromium） | Electron |
| 运行时依赖 | **零**——只调用 macOS 自带 WebKit，无需打包 Node/Chromium | 需打包 Node + Chromium（约 100MB+） | 需打包 Node + Chromium |
| 安装包体积 | 二进制约 180KB + 图标约 130KB（不含服务端） | DMG 安装包（数百 MB 级） | 安装包 |
| 构建方式 | `bash build.sh`，约 30 秒，仅需 Xcode CommandLineTools | 源码构建（pnpm / electron-builder） | 源码构建 |
| 平台 | macOS（arm64；Intel 可交叉编译） | macOS + Windows（签名/公证） | macOS + Windows |
| 服务启动方式 | 自动发现（settings → 3080 → lsof 扫描）→ 找不到才自起 `dsh web`，随机端口时从 stdout 解析真实地址 | 固定 spawn `dsh web`，等待就绪行 | 自动启动并管理本地服务 |
| 服务退出语义 | 只终止**自己启动**的服务；外部已有服务零干预 | 拥有 shutdown 与崩溃重启 | 集成管理（含系统托盘） |
| 高级配置 | `settings.json`（端口/URL/工作目录/dshPath/窗口尺寸） | — | — |
| 额外功能 | — | 崩溃自动重启 | 系统托盘、手机远程控制（规划中） |

一句话：**Electron 系把 Chromium 搬进来、面向下载分发**；本项目**零依赖、源码一键构建、面向自用与审计**——同样的"spawn `dsh web` → 解析就绪行 → 打开窗口 → 退出回收"模型，但整个壳只有几百 KB，构建产物可逐行审查。

## 安装

构建（约 30 秒，零外部依赖，仅需 Xcode CommandLineTools）：

```bash
bash build.sh        # 构建并安装到 ~/Desktop/DSH.app
```

构建产物同时保留在 `build/DSH.app`，可自行复制到 `/Applications`。

## 使用

双击 `DSH.app`。启动流程：

1. 按顺序探测服务：settings.json 指定地址 → 端口 3080 → 扫描运行中 dsh 进程的监听端口（`lsof` + DSH 指纹 `window.__DSH_BOOT__` 确认）
2. 找不到 → 自动启动 `dsh web`（3080 被非 DSH 进程占用时改用 `--port 0` 随机端口，从子进程 stdout 解析真实地址）
3. 窗口加载 Web UI；30 秒未就绪显示错误页（含"重试"）

退出（Cmd+Q）：只终止 App 自己启动的 dsh 进程（SIGTERM → 3s → SIGKILL，按进程组回收）；若服务在 App 启动前已在运行，退出时不做任何干预。

菜单：`重新加载`（Cmd+R）、`在浏览器中打开`（Cmd+Shift+O）、`退出`（Cmd+Q）。

## 配置（可选）

`~/Library/Application Support/DSH GUI/settings.json`：

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

| 键 | 作用 |
|---|---|
| `port` / `url` | 跳过自动发现，直接连接指定服务（url 优先） |
| `cwd` | 自起服务的工作目录（dsh 的默认文件系统位置）；默认 `$HOME` |
| `dshPath` | 显式指定 dsh CLI；默认按 `which dsh` → npx 缓存顺序定位 |
| `windowWidth` / `windowHeight` | 窗口初始尺寸 |

## 日志

`~/Library/Logs/dsh-gui.log`（启动、连接、终止记录 + dsh 子进程输出）。

## 测试

```bash
bash build.sh --test
```

- 单元测试：URL 解析 / DSH 指纹 / lsof·ps 端口发现 / 设置解析 / 启动命令构造
- 集成测试：假 dsh 脚本全链路（spawn → stdout 解析 → 连接回调 → 进程组回收）

## 设计文档

- 规格：`docs/superpowers/specs/2025-08-14-dsh-gui-design.md`
- 计划：`docs/superpowers/plans/2025-08-14-dsh-gui.md`
