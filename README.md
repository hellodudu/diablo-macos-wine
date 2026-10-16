# 在 Apple Silicon Mac 上跑《暗黑破坏神》——国服 D4 + 经典 D2 

用**纯免费/开源方案**，在 Apple 芯片 Mac（实测 M5 Pro / macOS 26.6.2）上跑起
**国服《暗黑破坏神 IV》** 与 **经典版《暗黑破坏神 II》**。

> **本仓库不含任何游戏内容。** 你需要拥有游戏的合法授权，游戏文件只能由你自己提供。
> 详见[法律与授权](#法律与授权)。

---

## 结果

| 目标 | 状态 |
|---|---|
| 国服《暗黑破坏神 IV》 | ✅ 可正常游玩（联网登录、图形与音频正常） |
| 经典版《暗黑破坏神 II》环境 | ✅ 已搭好并通过底层兼容性实测（等待你自己的合法安装器） |

**全程未使用任何付费产品或试用。** 引擎由 CodeWeavers 公开发布的 **GPL 源码**构建（或使用其社区预编译版），
Apple 的部分使用你自己从 Apple 下载的免费 Game Porting Toolkit。

---

## 一、国服 D4：核心结论

要让 D4 跑起来，**必须同时满足四个条件**。市面上的免费引擎**没有一个原生满足全部四条**，
这是很多人反复失败的根本原因。

| 条件 | 为什么需要 | GPTK Wine 7.7 | Gcenx Wine 11.9 | **CX 26.3 GPL + D3DMetal** |
|---|---|---|---|---|
| **A. Agent 授权** | 战网 Agent 要校验连接进程的身份 | ❌ 无限 401 | ✅ | ✅ **0 失败** |
| **B. DX12 FL 12_0** | D4 是 DX12 游戏，硬要求 | ✅ 12_0 | ❌ 只有 11_0 | ✅ **12_1** |
| **C. 客户端界面能渲染** | 客户端是 CEF（Chromium）界面 | ❌ | ❌ | ✅ |
| **D. 游戏能启动** | 加载器依赖 + Overlay 注入 | ❌ | ❌ | ✅ |

四个条件的详细原理、排查过程与实测数据见 **[diablo4/docs/FINDINGS.md](diablo4/docs/FINDINGS.md)**。
下面只给结论。

### 条件 A：Agent caller authorization

症状是战网客户端卡在 401 重试，Agent 日志：

```
[I] Unable to validate connecting process
[E] Failed Caller authorization due to signature for 'Battle.net.exe'
    -> Agent init returned status code=401
```

**真因**：Agent 要拿连接进程的 PID 解析出可执行文件路径，而 macOS 没有 `/proc`，
这需要 Wine 里有专门的代码路径。决定性证据是调试日志里
`WinVerifyTrust returning 00000002`（`ERROR_FILE_NOT_FOUND`）出现几十次——
它拿到的路径根本打不开文件，签名校验必然失败。

排查中被实测排除的三个猜测：缺 `ntlm_auth`（只是警告）、Windows 版本不够（`RtlGetVersion` 一直是 10.x）、
签名验证能力不足（传正确路径时 `WinVerifyTrust` 返回 0）。

**结论**：需要 **CodeWeavers 血统**的引擎。GPTK 自带的 Wine 7.7 会无限 401。

### 条件 B：DX12 feature level 12_0

用本仓库的 `d3d12check.c` 实测：

| 引擎 | D3D12CreateDevice(12_0) | 最高特性级别 |
|---|---|---|
| Gcenx Wine 11.9（MoltenVK + vkd3d） | ❌ `hr=0x80070057` | 11_0 |
| CX 26.3 GPL + Apple D3DMetal | ✅ | **12_1** |

**一个重要否定结论**：D3DMetal **不能靠拷贝文件接进** Gcenx Wine 11.9。
实测报 `unimplemented function ntdll.dll.__wine_unix_call` → `d3d12.dll failed to initialize`。
Apple 的垫片要求引擎侧 ABI 匹配，必须用 CodeWeavers 血统的引擎。

### 条件 C：客户端界面全黑（两层原因，缺一即黑）

**C-1 渲染进程 int3 崩溃** → 需要 `WINE_SIMULATE_WRITECOPY=1`。

症状：CEF 渲染进程反复重启，日志 `Unhandled exception 0x80000003 ... address ...00E1`
（`0x80000003` = `EXCEPTION_BREAKPOINT`，地址尾部与 `libcef.dll+0x16D00E1` 一致）。
根因是 CEF 渲染器断言「旧保护 == `PAGE_READWRITE`」，而纯 Wine 不追踪写时复制。
CrossOver 出货版默认开这个 hack，**GPL 源码里只能靠环境变量打开**。

**C-2 画面全黑但渲染器不崩、页面 HTTP 200** → 需要正确的启动方式。

这一层更隐蔽：客户端自己的 UI 能画、网页内容也加载成功（日志 `result=200`），但内容区全黑。
实测需要**两个改动同时生效**：

| 改动 | 单独使用的效果 |
|---|---|
| Wine 虚拟桌面（`explorer /desktop=...`） | 黑屏 → 白屏 |
| `--in-process-gpu --use-gl=swiftshader` | 配合虚拟桌面才出画面 |
| `WINE_CUSTOM_FRAME`（抑制 macOS 原生标题栏叠加） | 主窗口不再被标题栏挤压 |

根因：战网主窗口是**无边框**的，CEF 的内容要合成进这个窗口；
Wine 默认窗口路径下合成不进去，虚拟桌面提供了合成的载体。

> ⚠️ **一个反直觉的坑**：不能用「GL 错误条数」判断成败。
> 默认路径下 GL 错误为 **0** 却照样全黑；而界面最终能渲染的那套配置里 GL 错误反而有 9~12 条。
> 这些 `SharedImageStub` / `Failed to create GLES3 context` 报错是**无害噪声**。

### 条件 D：游戏能启动

**D-1 加载器硬查 `kernel32.FindNextFileNameW`。**
2026 年 5 月 D4 更新后 `diablo_iv_loader.dll` 会硬性查询这个 kernel32 导出；
Wine 曾经没有它就完全无法启动（暴雪论坛有 600+ 楼的长贴）。上游后来补了 stub。
本仓库的 `loadercheck.c` 可实测你机器上是否具备。

**D-2 Overlay 注入会卡死登录初始化。**
症状是**永久卡在「正在登录《暗黑破坏神IV》」，且无法正常关闭**。
解法有两条，本仓库采用后者：

- 禁用 Overlay —— **不推荐**：实测会导致客户端更新失败（`3_Z3NTAGT00000839`，AGT = Agent），
  因为 Agent 更新时需要校验/修复这些文件
- ✅ **直启 `Diablo IV.exe`**（本仓库的做法）：客户端不会注入 Overlay，天然绕开

**D-3 启动的命令行**（三条路的实测对比）：

| 方式 | 结果 |
|---|---|
| `Diablo IV Launcher.exe` | ❌ 没有 SSO 令牌，MoltenVK 初始化后就没下文 |
| `Battle.net.exe --exec="launch <uid>"` | ❌ 只触发更新检查，不会启动游戏 |
| ✅ `Diablo IV.exe -nostreamline -sso -launch -uid <uid>`（客户端在运行） | ✅ 可用 |

---

## 二、快速开始

### 前置

1. Apple 芯片 Mac（M1 或更新），macOS 26 或更新
2. Rosetta 2：`softwareupdate --install-rosetta`
3. Apple Game Porting Toolkit（[Apple 开发者下载](https://developer.apple.com/games/game-porting-toolkit/)，免费，需登录 Apple ID）
4. 一个 CodeWeavers GPL 源码构建的 Wine 引擎
   （社区预编译版：[Soju](https://github.com/BCD1210/soju) 的 `engine-*` release，
   或自行用其 `scripts/build-engine.sh` 从 CodeWeavers 公开发布的源码构建）
5. **你自己合法拥有的国服《暗黑破坏神 IV》**，以及国服战网账号（需绑定网易通行证）

### 步骤

```bash
# 1. 把引擎与 D3DMetal 载荷准备好（见 diablo4/docs/FINDINGS.md 第二节）
#    引擎目录结构：<engine>/bin/wine, <engine>/lib/...

# 2. 改脚本里的路径
$EDITOR diablo4/scripts/env.sh      # 至少确认 SOJU_ENGINE 与引擎可用

# 3. 装战网客户端（国服安装器需你自己下载）
diablo4/scripts/install-battlenet.sh

# 4. 启动客户端，登录（凭据由你本人输入）
diablo4/scripts/run-battlenet.sh

# 5. 在客户端里安装 D4

# 6. 启动游戏（客户端需保持运行，它负责提供 SSO 令牌）
diablo4/scripts/run-d4.sh

# 随时体检（逐条验证四个条件）
diablo4/scripts/status.sh
```

### 关于窗口大小

客户端跑在 Wine 虚拟桌面里，**窗口不可拖动缩放**（虚拟桌面是无边框 popup 窗口的固有代价）。
启动时用变量定尺寸即可：

```bash
DM_DESKTOP_SIZE=1920x1080 diablo4/scripts/run-battlenet.sh
```

也可以试 `DM_USE_DESKTOP=0 diablo4/scripts/run-battlenet.sh` 关掉虚拟桌面——
那样窗口是普通 macOS 窗口、可自由缩放，但界面**有可能又变黑**（这正是当初启用它的原因）。

---

## 三、经典版 D2（附）

同一套思路也用于经典版《暗黑破坏神 II》。经典版的优势是**不需要战网启动器**，单机、局域网全功能。
本仓库提供：双击启动器、环境自检、Glide 3D 包装器安装、以及一个 32 位 DirectDraw/D3D/OpenGL 实测程序。

详见 **[diablo2-classic/README.md](diablo2-classic/README.md)**。

---

## 四、目录结构

```
.
├── README.md                      ← 你在这里
├── diablo4/                       ← 国服 D4（主项目）
│   ├── README.md                  ← 操作手册
│   ├── docs/FINDINGS.md           ← 四个条件的原理与实测数据（技术核心）
│   ├── scripts/
│   │   ├── env.sh                 ← 唯一配置入口
│   │   ├── run-battlenet.sh       ← 启动客户端
│   │   ├── run-d4.sh              ← 启动游戏
│   │   ├── install-battlenet.sh   ← 跑官方安装器
│   │   ├── status.sh              ← 逐条体检四个条件
│   │   ├── disable-overlay.sh     ← 应急用（默认拒绝执行，见文件头警告）
│   │   └── setup-prefix.sh.obsolete
│   └── tools/                     ← 四个自编诊断程序（C 源码）
│       ├── sigcheck.c             ← WinVerifyTrust 签名验证能力
│       ├── vercheck.c             ← 权威系统版本（32/64 位）
│       ├── d3d12check.c           ← DX12 / DXGI 能力
│       └── loadercheck.c          ← D4 加载器依赖
└── diablo2-classic/               ← 经典版 D2
    ├── README.md
    ├── docs/verification-2026-10-15.txt   ← 实测原始输出
    ├── scripts/
    └── tools/d2check.c
```

---

## 五、本仓库刻意不含的东西

| 不含 | 原因 |
|---|---|
| 任何游戏文件（程序、美术、音频、数据表） | 版权；请使用你自己的合法拷贝 |
| 编译好的 `.exe` | 源码在 `tools/`，自行编译（见下） |
| Sven's Glide Wrapper | 第三方免费软件，[官网](https://www.svenswrapper.de/)自行下载 |
| 引擎二进制、Wine 前缀、日志 | 体积大，且属游戏文件的派生物 |

### 编译诊断工具

```bash
brew install mingw-w64

# 32 位
i686-w64-mingw32-gcc -O1 -o sigcheck32.exe sigcheck.c -lwintrust
i686-w64-mingw32-gcc -O1 -o vercheck32.exe vercheck.c
i686-w64-mingw32-gcc -O1 -o d2check32.exe  d2check.c -lddraw -ldxguid -lopengl32 -lgdi32 -luser32

# 64 位
x86_64-w64-mingw32-gcc -O1 -o d3d12check64.exe d3d12check.c -ld3d12 -ldxgi -ldxguid -luuid
x86_64-w64-mingw32-gcc -O1 -o loadercheck64.exe loadercheck.c
x86_64-w64-mingw32-gcc -O1 -o vercheck64.exe vercheck.c
```

运行（注意 `DYLD_FALLBACK_LIBRARY_PATH`，且**不要**经 `arch`/`nohup`，它们会剥掉 `DYLD_*`）：

```bash
ENGINE=~/path/to/engine
WINEPREFIX=~/path/to/prefix \
DYLD_FALLBACK_LIBRARY_PATH="$ENGINE/lib:/usr/lib" \
ROSETTA_ADVERTISE_AVX=1 WINE_SIMULATE_WRITECOPY=1 \
  "$ENGINE/bin/wine" 'Z:\path\to\d3d12check64.exe'
```

---

## 六、踩过的坑（按代价排序）

1. **用「GL 错误条数」当成功判据** —— 无效。默认路径 0 条错误却全黑；能渲染的配置反而有 9~12 条。
   真正的判据是**画面**，以及进程是否真的在跑（`ps` 确认 + 客户端是否产生新日志）。
2. **日志里没有错误 ≠ 启动成功** —— 曾经因为 tar 解压静默失败（`2>/dev/null` 吞掉了报错），
   可执行文件不存在，启动直接失败，日志里自然一条错误都没有，我据此得出了错误结论。
3. **`arch -x86_64` / `nohup` 会剥掉 `DYLD_*`** —— 导致 `freetype`/`gnutls` 加载失败、界面无字体。
   必须直接执行引擎的 `bin/wine`。
4. **默认 `WINEDEBUG` 会让 wine 狂刷日志** —— 一次启动写出过 **21 GB** 日志。
   必须设 `WINEDEBUG=-all,-fixme`。
5. **照抄别人的环境变量会引入回归** —— `WINEMSYNC=1` 在本机引擎上会让程序直接死掉（rc=1、零输出）。
   加任何变量都应做对照实验。
6. **只看注册表 `CurrentVersion` 判断 Windows 版本** —— 那是遗留字符串（一直显示 6.3），
   应用实际读的是 `RtlGetVersion`（一直是 10.x）。要测就用 `vercheck`。
7. **禁用 Overlay 会破坏客户端更新** —— 报 `3_Z3NTAGT00000839`。而直启 D4 本就不需要禁用它。

---

## 法律与授权

- **你必须拥有游戏。** 本仓库是独立、非商业的技术记录，与暴雪娱乐、网易、Nintendo 无关联，
  未获其背书或赞助。Diablo 与 Blizzard Entertainment 是暴雪娱乐的商标。
- **本仓库不含任何游戏内容**，也不提供获取途径。请只使用你自己合法拥有的游戏文件。
  请勿在 issue 或 PR 中粘贴游戏文件或下载地址。
- 本仓库记录的是**接口事实**（宿主如何与游戏对接、需要哪些平台能力），不是游戏内容本身。

## 致谢

- **[Soju](https://github.com/BCD1210/soju)** —— 本项目的引擎与大量排查思路来自它。
  其作者从 CodeWeavers 公开发布的 GPL 源码构建引擎，并把每一个坑都写成了文档，
  尤其是 `docs/DIAGNOSIS.md` 里关于 CEF 渲染进程崩溃与 Agent 签名失败的深度分析。
- **CodeWeavers** —— CrossOver 的 Wine 源码以 GPL 发布。
- **Apple** —— Game Porting Toolkit / D3DMetal（免费下载，禁止再分发，本项目不含其任何文件）。
- **mingw-w64**、**MoltenVK**。

## 许可

本仓库的脚本与文档：MIT（见 [LICENSE](LICENSE)）。
第三方组件（引擎、GPTK、Glide Wrapper 等）各自遵循其原始许可。
