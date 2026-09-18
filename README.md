# DeepSeek Harness Desktop

DeepSeek Harness 桌面端（Windows 11 x64）应用源码。

本仓库仅包含**桌面端应用自身的源码**（Electron 客户端与桌面宿主进程），不含 DeepSeek Harness 官方 monorepo 的其余部分（CLI、Web、文档、Python SDK、Benchmark 等）。完整可构建的工作区请使用官方项目：

> 官方仓库：`deepseek-ai/deepseek-harness-dsh`（monorepo，`pnpm@11.7.0`，版本 `0.1.6-alpha.2`）

---

## 仓库结构

```
deepseek-harness-desktop
├── apps/
│   ├── desktop/          # Electron 44 桌面客户端（主进程、渲染层、安装器、打包脚本）
│   │   ├── src/          # 主进程与预加载脚本（main.ts / preload-app.cjs 等）
│   │   ├── renderer/     # 桌面端渲染层（更新对话框、强制更新页、策略登录页）
│   │   ├── installer/    # NSIS 安装器自定义界面（品牌图、窗口框架 C++ 源码、NSH 脚本）
│   │   ├── resources/    # 应用图标（Windows / macOS）
│   │   ├── scripts/      # 打包流水线（package-target / prepare-runtime / windows-sign 等）
│   │   ├── tests/        # 打包与主进程单元测试
│   │   ├── electron-builder.config.mjs
│   │   └── package.json  # @deepseek-ai/dsh-desktop
│   └── desktop-host/     # 桌面宿主进程（Host 运行入口，@deepseek-ai/dsh-desktop-host）
├── LICENSE               # MIT（Copyright (c) 2026 DeepSeek）
└── README.md             # 本文件（开发说明）
```

## 依赖关系说明

桌面客户端通过 pnpm workspace 依赖官方 monorepo 中的 Host 组件：

- `@deepseek-ai/dsh-app-boot`（应用启动编排）
- `@deepseek-ai/dsh-home-paths`（数据目录解析）

因此本仓库**不能脱离官方 monorepo 独立构建**。开发时请将本仓库的 `apps/desktop`、`apps/desktop-host` 放入官方 monorepo 的 `apps/` 目录下（或直接在官方 monorepo 内以本仓库内容覆盖对应目录），再按下面流程操作。

---

## 环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 11 x64（构建宿主） | 仅支持 Windows 宿主构建 win-x64 目标 |
| Node.js | **22.23.x（官方版）** | Node 24.16+ 的 `extract-zip` 有冻结回归；Node 22 的 `fs.cpSync` 在**含中文的路径**下会原生崩溃（0xC0000409），源码路径请使用 ASCII 字符 |
| pnpm | 11.7.0（corepack 锁定） | 与官方 `packageManager` 一致 |
| 构建工具 | Visual Studio 2022 Build Tools（含 VC.Tools.x86.x64 + Windows SDK） | 安装器自定义窗口框架 `window-frame.dll` 需要 `cl.exe` 编译 |
| 内存 | 建议 8 GB 以上 | 构建高峰（tsc 4GB 堆 + 打包）在 8 GB 机器上内存吃紧，可能触发图标转换 WASM 分配失败 |

## 快速开始

```powershell
# 1. 在官方 monorepo 内准备环境
#    （Node 22.23.x 置于 PATH 首位；corepack 准备的 pnpm 11.7.0）

# 2. 安装依赖（复用 store，约 2~14 分钟）
pnpm install --frozen-lockfile

# 3. 配置发布环境（复制模板）
cd apps/desktop
Copy-Item .env.windows.example .env.windows
#    编辑 .env.windows：
#    DSH_DESKTOP_APP_ID=com.deepseek.harness
#    DSH_DESKTOP_AUTO_UPDATE_ENV=test
#    DSH_DESKTOP_MANDATORY_UPDATE_TEST_ORIGIN=https://harness-test.deepseek.com
#    DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN=https://harness.deepseek.com
cd ..\..
```

## 构建

### 免签名（本地开发 / 无 EV 证书）—— 推荐

官方流水线自带免签名通道（`DSH_DESKTOP_UNSIGNED=1`），产物输出到 `unsigned-artifacts/`：

```powershell
# 安装包（NSIS，含自定义安装界面）
pnpm run package:desktop:win:x64:unsigned

# 免安装目录版（win-unpacked，可压缩为 portable.zip 分发）
# 在 apps/desktop 下执行：
pnpm exec tsx scripts/package-target.ts win-x64 --dir --unsigned
```

完整流水线：`build:official`（tsc + tsdown）→ `release:pack`（dsh/vendor/landlock）→ `prepare:runtime`（下载校验 Node 24.17.0 运行时）→ `prepare:packages` → `prepare:dsh`（离线物化依赖）→ electron-builder。

产物位置：`apps/desktop/.desktop-build/targets/win-x64/unsigned-artifacts/`
- `deepseek-harness-<version>-win-x64.exe`（安装包）
- `deepseek-harness-<version>-win-x64.exe.blockmap`（增量更新映射）
- `win-unpacked/`（免安装目录，zip 后即免安装版）

### 签名版（正式发布，需 EV 证书）

```powershell
# 在 .env.windows 配置四件套后：
# DSH_DESKTOP_WINDOWS_CER_FILE / SIGNTOOL / KEY_CONTAINER / TOKEN_PIN
pnpm run package:desktop:win:x64
```

### 已知坑

- **图标转换内存不足**：electron-builder 的 PNG→ICO 转换（WASM）在可用内存过低时会报
  `WebAssembly.Memory(): could not allocate memory`。可预先用非 WASM 工具生成多尺寸 `.ico`
  并追加参数 `--config.win.icon=<path>.ico` 绕过。
- **lefthook pre-push 钩子**：安装依赖后 pre-push 会执行 typecheck，若 PATH 里的 pnpm 指向损坏的
  corepack shim（Node 20），会报 `ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`。确保 PATH 首位是
  Node 22.23.x 与可用 pnpm，或对纯源码同步使用 `git push --no-verify`。
- **内存耗尽**：8 GB 机器在 `prepare:dsh` / 打包阶段可能内存耗尽导致系统冻结，注意监控
  `FreePhysicalMemory`，必要时分阶段重试（已下载的 Node 与依赖可复用）。

## 测试

```powershell
# 桌面包单元测试
pnpm --filter @deepseek-ai/dsh-desktop test:installer
pnpm --filter @deepseek-ai/dsh-desktop test:updates:local   # 需先 build

# 打包配置校验（不实际打包）
pnpm --filter @deepseek-ai/dsh-desktop run check:package
```

## 发布流程

```powershell
git tag -a v<version> -m "DeepSeek Harness v<version>"
git push origin v<version>

# 创建 Release 并附加产物（exe + portable.zip + blockmap）
gh release create v<version> --repo <owner>/deepseek-harness-desktop `
  --title "DeepSeek Harness v<version>" `
  --notes-file release-notes.md `
  <path>\deepseek-harness-<version>-win-x64.exe `
  <path>\deepseek-harness-<version>-win-x64-portable.zip `
  <path>\deepseek-harness-<version>-win-x64.exe.blockmap
```

## 注意事项

- 免签名产物首次运行会被 SmartScreen 提示，选择"仍要运行"即可；正式分发需配置 EV 证书重新打包。
- 应用内自动更新源默认指向测试占位地址（`desktop-updates.example.com` 等），正式发布前需配置真实更新服务。
- `DSH_CLIENT_COMMIT_HASH` 由构建自动取当前 Git HEAD（7 位短哈希）；无 Git 元数据时可用环境变量显式指定。

## License

MIT License — Copyright (c) 2026 DeepSeek。详见 [LICENSE](./LICENSE)。
