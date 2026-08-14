# DSH GUI — DeepSeek Harness 桌面客户端

macOS 原生桌面 App：双击图标即打开 DeepSeek Harness Web UI（独立窗口，内置 WebKit），自动发现或启动 DSH 服务，退出时仅关闭自己启动的服务。

## 安装

构建（约 30 秒，零外部依赖，仅需 Xcode CommandLineTools）：

```bash
cd dsh-gui
bash build.sh        # 构建并安装到 ~/Desktop/DSH.app
```

构建产物同时保留在 `dsh-gui/build/DSH.app`，可自行复制到 `/Applications`。

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

- 规格：`../docs/superpowers/specs/2025-08-14-dsh-gui-design.md`
- 计划：`../docs/superpowers/plans/2025-08-14-dsh-gui.md`
