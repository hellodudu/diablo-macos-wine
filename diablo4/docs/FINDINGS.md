# 技术findings：四个条件与引擎组装

本文是[主仓库 README](../../README.md)结论的展开，包含**可复现的组装步骤**与**原始实测数据**。

---

## 〇、总览：为什么必须自己拼一个引擎

要跑国服 D4，引擎必须同时满足四个条件。**没有任何一个现成的免费引擎全部满足**：

| 引擎 | A. Agent 授权 | B. DX12 12_0 | C. 客户端界面 | D. 游戏启动 |
|---|---|---|---|---|
| Apple GPTK 自带 Wine 7.7 | ❌ 无限 401 | ✅ | ❌ | — |
| Gcenx Wine Staging 11.9 | ✅ | ❌ 仅 11_0 | ❌ | — |
| Kegworks / Whisky 系 | ❌ | ❌ | ❌ | — |
| **CX 26.3 GPL 引擎 + Apple D3DMetal 载荷** | ✅ | ✅ | ✅ | ✅ |

关键判断：**A 与 B 分属两个不同来源，必须拼在一起**。

- A 需要 **CodeWeavers 血统**（macOS 上的 PID→路径解析）
- B 需要 **Apple 的 D3DMetal**（且它只能接进 CodeWeavers 血统的引擎，见第一节末）

---

## 一、组装引擎

### 1.1 取得一个 CodeWeavers 血统的引擎

两条路，都用**公开的 GPL 源码**，不涉及付费产品：

**路线一：用社区预编译版（快）**

```bash
# Soju 的引擎 release，约 367 MB
curl -fL -o wine-engine.tar.xz \
  "https://github.com/BCD1210/soju/releases/download/engine-v1.5/wine-engine-x86_64.tar.xz"
mkdir -p engine && tar -xJf wine-engine.tar.xz -C engine
engine/bin/wine --version        # 应输出 wine-11.0
```

**路线二：从 CodeWeavers 公开发布的源码自建**

```bash
# 源码包在 CodeWeavers 自己的服务器上，公开可取
curl -fL -o crossover-sources.tar.gz \
  "https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz"
# 构建脚本（需要 Xcode CLT + Homebrew）：
#   https://github.com/BCD1210/soju/blob/main/scripts/build-engine.sh
```

### 1.2 接入 Apple 的 D3DMetal 载荷（三部分，缺一不可）

这一节是整个项目最容易做错的地方。Apple 的 GPTK 载荷**必须分三部分同时到位**，
任何一部分缺失都不会报出明显错误，只会表现为「界面能画一点、内容全黑」。

设 `ENGINE=<引擎目录>`、`GPTK=<GPTK.app>/Contents/Resources/wine`，则：

```bash
# 第 1 部分：Metal 侧
mkdir -p "$ENGINE/lib/external"
cp -Rf "$GPTK/lib/external/." "$ENGINE/lib/external/"
#   得到 D3DMetal.framework + libd3dshared.dylib

# 第 2+3 部分：Apple 的 PE 垫片 + unix 侧 symlink
for f in "$GPTK"/lib/wine/x86_64-unix/*.so; do
  [ -L "$f" ] || continue                    # 只处理 symlink（那才是 Apple 的垫片）
  b="$(basename "$f" .so)"
  # 用特征串确认它确实是 Apple 的垫片，而不是 Wine 自带的 DLL
  grep -qa "D3DMetalDLLsBase" "$GPTK/lib/wine/x86_64-windows/$b.dll" || continue
  cp -f "$GPTK/lib/wine/x86_64-windows/$b.dll" "$ENGINE/lib/wine/x86_64-windows/$b.dll"
  ln -sf ../../external/libd3dshared.dylib "$ENGINE/lib/wine/x86_64-unix/$b.so"
done
```

会搬到这些模块（视 GPTK 版本略有差异）：
`d3d10 / d3d11 / d3d12 / dxgi / atidxx64 / nvapi64 / nvngx / nvngx-on-metalfx`

**校验（照 Soju 的 `GPTK_OK` 判据）：**

```bash
[ -f "$ENGINE/lib/external/libd3dshared.dylib" ] || echo "缺第 1 部分"
for f in d3d11 d3d12 dxgi; do
  grep -qa "D3DMetalDLLsBase" "$ENGINE/lib/wine/x86_64-windows/$f.dll" || echo "缺 $f 的垫片"
  [ -L "$ENGINE/lib/wine/x86_64-unix/$f.so" ] || echo "$f.so 不是 symlink"
done
```

> ⚠️ **第三部分必须是 symlink**。拷成实体文件会破坏 `@loader_path` 解析，
> D3DMetal 会在断言循环里死掉。

### 1.3 一个重要的否定结论：不能拷进普通 Wine

把上面那套载荷原样拷进 Gcenx 的 Wine 11.9 会失败：

```
wine: Call from ... to unimplemented function ntdll.dll.__wine_unix_call, aborting
err:module:loader_init "d3d12.dll" failed to initialize, status 80000100
```

Apple 的垫片要求引擎侧 ABI 匹配。**必须用 CodeWeavers 血统的引擎**，这条路没有捷径。

---

## 二、条件 A：Agent caller authorization

### 2.1 症状

战网客户端启动后无限重试，Agent 日志（`C:\ProgramData\Battle.net\Agent\Agent.*\Logs\Agent-*.log`）：

```
[I] Unable to validate connecting process (32)
[E] Failed Caller authorization due to signature for 'Battle.net.exe'(PID)
    -> Agent init returned status code=401
```

### 2.2 定证过程

三个直觉猜测**全部被实测排除**：

| 猜测 | 实测方法 | 结论 |
|---|---|---|
| 缺 `ntlm_auth`（NTLM 不支持） | 看日志 | ❌ 只是 `err:winediag:ntlm_check_version` 警告，非 401 来源 |
| Windows 版本不够（注册表 `CurrentVersion` = 6.3） | 自编 `vercheck.c` 读 `RtlGetVersion` | ❌ 一直是 **10.0 build 19045**；6.3 是应用不读的遗留字符串 |
| 签名验证能力不足 | 自编 `sigcheck.c` 调 `WinVerifyTrust` | ❌ 传正确路径时返回 **0（成功）** |

真正的证据来自一次 `WINEDEBUG=+wintrust` 的调试日志（274 MB）：

```
WinVerifyTrust returning 00000002   ← 58 次
WinVerifyTrust returning 00000000   ← 12 次
```

`0x00000002` = `ERROR_FILE_NOT_FOUND`。**Agent 拿 PID 解析出的可执行文件路径打不开**
（macOS 没有 `/proc`），于是签名校验必然失败。

历史旁证：被排查的四个旧前缀里，`Failed Caller authorization` 累计数百次，
而**成功授权 0 次**；其中 `Battle.net.exe` 本身就失败 2557+ 次，
所以「用 GPTK 渲染 + 别处装」的混合方案也不成立。

### 2.3 引擎代次对照

| 引擎 | `lib/wine` 模块 | Agent 授权 |
|---|---|---|
| GPTK Wine 7.7 | 含 `x86_32on64-unix`（旧式 WoW64） | ❌ 无限 401 |
| **CX 26.3**（CodeWeavers 血统） | `i386-windows` `x86_64-unix` `x86_64-windows` | ✅ **0 次失败** |

---

## 三、条件 B：DX12

用 `tools/d3d12check.c` 实测：

**Gcenx Wine 11.9（MoltenVK + vkd3d）：**

```
[ OK ]  CreateDXGIFactory1 —— DXGI 可用
[ OK ]  适配器[0]: NVIDIA GeForce 6800 (显存 38338 MB)     ← Wine 对未知厂商的占位名
[FAIL]  D3D12CreateDevice(12_0)  (hr=0x80070057)
[ OK ]  D3D12CreateDevice(11_0) 成功（仅 11_0 特性级别）
结论：DX12 不可用
```

**CX 26.3 + Apple D3DMetal（同一个程序，同一台机器）：**

```
[ OK ]  适配器[0]: AMD Compatibility Mode  (显存 38338 MB)
[ OK ]  D3D12CreateDevice(12_0) 成功 —— DX12 可用，D4 具备渲染前提
[ OK ]  最高支持特性级别: 12_1
```

---

## 四、条件 C：客户端界面（两层原因）

### 4.1 C-1：CEF 渲染进程 int3 崩溃

**症状**：CEF 渲染进程反复重启；日志

```
wine: Unhandled exception 0x80000003 in thread 340 at address 68FA00E1
```

`0x80000003` = `EXCEPTION_BREAKPOINT`；地址尾部 `00E1` 与已知的 `libcef.dll+0x16D00E1` 一致。

**根因**（来自 Soju `docs/DIAGNOSIS.md` 的反汇编结论）：CEF 渲染器执行

```c
ret = VirtualProtect(addr, size, PAGE_READONLY, &old);
if (!ret)                          int3;   // 0x16D00DE
if (old != PAGE_READWRITE)         int3;   // 0x16D00E1  ← 死在这里
```

`addr` 是 `libcef.dll` 的 `.data` 页。纯 Wine 一开始就把可写页 mmap 成 RW 且不追踪写时复制，
所以 `old` 永远是 `PAGE_WRITECOPY(8)`，而 Windows 在首次写入后会变成 `PAGE_READWRITE(4)`。

CrossOver 源码里有模拟这个行为的 hack（CW Hack 22996 / `simulate_writecopy`），
但**公开源码里只能靠环境变量打开**：

```sh
export WINE_SIMULATE_WRITECOPY=1
```

修复前后对照：

| | 异常次数 | 渲染器被终止 | 登录页 |
|---|---|---|---|
| 未设 | `0x80000003` × 1 | — | 黑屏 |
| 设了 | **0** | **0** | `finished loading. statusCode=200` |

### 4.2 C-2：画面全黑（渲染器不崩、页面 200）

**症状**：客户端自己的 UI 能画（标题栏、logo），网页内容也加载成功
（日志 `End recording load sequence for browser content_browser (Webview); result=200`），
但内容区全黑。

**根因**：战网**主窗口是无边框的**，CEF 要把内容合成进这个窗口。
Wine 默认的窗口路径下合成不进去。

**修法：两个改动必须同时生效**

```bash
export WINE_CUSTOM_FRAME="Battle.net.exe;Battle.net Launcher.exe"   # 抑制 macOS 原生标题栏叠加
wine explorer /desktop=BattleNet,1600x1000 \
     'C:\Program Files (x86)\Battle.net\Battle.net.exe' \
     --disable-gpu-compositing --from-launcher --in-process-gpu --use-gl=swiftshader
```

实测演进过程（每一步都请用户截图确认）：

| 配置 | 画面 |
|---|---|
| 走 `Battle.net Launcher.exe`，无虚拟桌面 | 全黑 |
| + `WINE_CUSTOM_FRAME` | 全黑，但原生标题栏消失 |
| + Wine 虚拟桌面 | **白屏**（有进展：窗口终于被合成） |
| + CEF 注入参数（`--in-process-gpu --use-gl=swiftshader`） | ✅ **界面完整渲染** |

> `--in-process-gpu --use-gl=swiftshader` 这两个参数在 CrossOver 里是从它**私有的加密兼容数据库**
> （`compatdb-*.dat`）在 ntdll 内部注入的，而 `Battle.net Launcher.exe` 只转发前两个参数
> （`--disable-gpu-compositing --from-launcher`）。所以必须**直启 `Battle.net.exe`** 并把它们写在命令行上。

### 4.3 ⚠️ 一个失效的判据

**不要用「GL 错误条数」判断成败。** 实测：

| 配置 | GL 错误条数 | 画面 |
|---|---|---|
| 走 Launcher（默认路径） | **0** | 全黑 |
| 虚拟桌面 + CEF 参数 | 9~12 | ✅ 正常渲染 |

`SharedImageStub: unable to create context`、`Failed to create GLES3 context`、
`WSALookupServiceBegin failed` 这几条是**无害噪声**——真正的 CrossOver 出货版同样会刷这些。

---

## 五、条件 D：游戏能启动

### 5.1 加载器硬查 `kernel32.FindNextFileNameW`

2026 年 5 月 D4 更新后，`diablo_iv_loader.dll` 会硬性查询这个 kernel32 导出；
Wine 当时没有它就完全无法启动（暴雪官方论坛该帖 600+ 楼）。上游后来补了 **stub**。

用 `tools/loadercheck.c` 实测本机引擎：

```
[ OK ]  kernel32.FindFirstFileNameW 存在
[ OK ]  kernel32.FindNextFileNameW 存在
[ OK ]  FindNextFileNameW 运行时可解析
[ OK ]  用无效句柄调用返回 FALSE（err=120）—— 行为正确，非崩溃
```

`err=120` = `ERROR_CALL_NOT_IMPLEMENTED`，即它是 stub。**这与上游修法一致**：
社区结论就是「加 stub 即可」，加载器只做存在性检查。

### 5.2 Overlay 注入卡死登录

**症状**（CrossOver 中文官网 2026-07-27 文档记录）：

> 2026 年 5 月更新后 Mac 用户无法登录，**卡在「正在登录《暗黑破坏神IV》」，且无法正常关闭**。
> 原因是战网 Overlay 组件在 Wine 环境下注入 D4 时卡住了登录后的初始化流程。

**两条解法：**

| 解法 | 评价 |
|---|---|
| 禁用 Overlay（重命名/占位那三个文件） | ⚠️ **不推荐**。见 5.3 |
| ✅ **直启 `Diablo IV.exe`** | 客户端不注入 Overlay，天然绕开 |

### 5.3 为什么本仓库不禁用 Overlay

Overlay 有**两份副本**：

- `C:\Program Files (x86)\Battle.net\Battle.net-<ver>\bdk\`
- `C:\ProgramData\Battle.net\bdk\` ← **客户端启动游戏时实际使用的是这份**

```
[GameLaunchController] Using agent overlay binary: C:/ProgramData/Battle.net/bdk\battlenet.overlay.runtime.exe
[GameLaunchController] PostLaunchChildProcess status: launchAction=Overlay uid=fenris
```

踩过的两个坑：

1. **只禁用 Program Files 那份没用** —— 客户端用的是 ProgramData 那份，D4 照样卡住。
2. **单纯改名会被客户端修复** —— 客户端启动游戏前会校验并重新下载。
   改用「0 字节占位 + `chflags uchg` 不可变」也**没拦住**（客户端仍换回了完整文件）。
3. **更糟的是：禁用 Overlay 会让客户端更新失败**，报
   `3_Z3NTAGT00000839`（AGT = Agent）——因为 Agent 更新时需要校验/修复这些文件，
   文件被改名/置空/不可写，它就修不了。

**所以本仓库改为不禁用 Overlay，靠直启游戏绕开。**
`scripts/disable-overlay.sh` 保留为应急工具，但**默认拒绝执行**，需显式 `--force`，
并提供 `--restore` 还原。

### 5.4 启动命令行（三条路实测）

| 方式 | 结果 |
|---|---|
| `Diablo IV Launcher.exe` | ❌ 没有 SSO 令牌，MoltenVK 初始化后没有下文 |
| `Battle.net.exe --exec="launch fenris"` | ❌ 只触发更新检查，不会启动游戏 |
| ✅ `Diablo IV.exe -nostreamline -sso -launch -uid fenris` | ✅ 可用（**客户端必须已运行并登录**） |

`-sso` 表示单点登录，令牌由战网客户端通过本地 IPC 提供。

---

## 六、环境变量总表

| 变量 | 何时需要 | 作用 |
|---|---|---|
| `DYLD_FALLBACK_LIBRARY_PATH="<engine>/lib:/usr/lib"` | **总是** | 找不到它则 `freetype`/`gnutls` 加载失败、界面无字体 |
| `WINE_SIMULATE_WRITECOPY=1` | **总是** | 缺了 CEF 渲染器 int3 崩溃 |
| `ROSETTA_ADVERTISE_AVX=1` | **总是** | D4 加载器要求 AVX；Rosetta 2 支持 AVX 但只有这个未公开变量才会对外声明。缺了会卡在图形初始化前（约 86 MB 内存、0% CPU） |
| `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`、`CX_GRAPHICS_BACKEND=d3dmetal` | 游戏 | 显式指定走 D3DMetal |
| `CX_APPLEGPTK_LIBD3DSHARED_PATH=<engine>/lib/external/libd3dshared.dylib` | 游戏 | 显式指定 libd3dshared 路径 |
| `D3DM_SUPPORT_DXR=1` | 游戏 | 让 D3DMetal 暴露 DXR |
| `WINE_CUSTOM_FRAME="Battle.net.exe;Battle.net Launcher.exe"` | 客户端 | 抑制 macOS 原生标题栏叠加在自绘无边框窗口上 |
| `WINEDEBUG=-all,-fixme` | **总是** | 否则默认调试输出会写出 GB 级日志（实测一次 21 GB） |
| `WINEMSYNC` | **不要设** | 见下 |

### 不要设 `WINEMSYNC`

Soju 的 `play.sh` 设了 `WINEMSYNC=1`，但**本机引擎上会把程序直接搞死**。对照实验：

| 配置 | 结果 |
|---|---|
| 基线 | ✅ rc=0，D3D12 FL 12_1 |
| 加 `CX_*` 后端变量 | ✅ rc=0，D3D12 FL 12_1 |
| **加 `WINEMSYNC=1`** | ❌ **rc=1，无任何输出** |

推测原因：msync 需要在 `wineserver` 启动时就协商，而现场已有非 msync 的服务在跑，客户端带上它就不匹配。

> **教训**：照抄别人的配方会引入回归。每加一个变量都应做对照实验。

---

## 七、排查手册

| 症状 | 先查什么 |
|---|---|
| 战网 Agent 无限 401 | 引擎血统（条件 A）。看 Agent 日志有没有 `Failed Caller authorization` |
| 客户端界面全黑 | ① `WINE_SIMULATE_WRITECOPY=1` 是否设 ② 是否用虚拟桌面 ③ 是否带 CEF 参数 ④ `WINE_CUSTOM_FRAME` |
| 界面无字体/方块 | `DYLD_FALLBACK_LIBRARY_PATH` 是否设；**是否经了 `arch`/`nohup`**（会剥掉 `DYLD_*`） |
| D4 卡在「正在登录」 | 是否直启了 `Diablo IV.exe`（而不是 Launcher 或客户端 Play 按钮） |
| D4 启动即退/无日志 | 客户端是否在运行（SSO 令牌来源）；命令行是否带 `-sso -launch -uid <uid>` |
| 客户端更新报 `3_Z3NTAGT...` | Overlay 文件是否被改名/置空/加了不可变标记 → `disable-overlay.sh --restore` |
| DX12 只有 11_0 | D3DMetal 载荷三部分是否齐全（第一节） |
| 日志体积爆炸 | `WINEDEBUG` 是否设成 `-all,-fixme` |

### 一个通用的验证纪律

判断「是否真的启动成功」的可靠指标，**不是日志里没有错误**，而是：

1. `ps` 里能看到进程，且 **CPU 不为 0**（0% 通常意味着卡死）
2. **客户端产生了新的日志文件**（对比启动前后）
3. 最终以**画面**为准

本项目走过一次弯路：tar 解压静默失败（`2>/dev/null` 吞掉报错）导致可执行文件不存在，
启动直接失败，日志里一条错误都没有——我据此得出了「成功」的错误结论。
**没有输出 ≠ 成功；要先确认进程真的在跑。**

---

## 八、关于 Mac x86_64（Intel）

### 8.1 结论：脚本可用，但 D4 跑不起来

**D4 在 Intel Mac 上无法运行，原因是 Apple 的支持范围，不是脚本缺陷。**

Apple 官方 Game Porting Toolkit 仓库的 `Prerequisites` 第一条原文：

```
- A Mac with Apple silicon.
```

而 D4 需要的 DX12 feature level 12_0 **只能来自 D3DMetal**（条件 B，见第三节），
D3DMetal 由 GPTK 提供。因此在 Intel Mac 上条件 B 无法满足，
D4 会在 DX12 初始化阶段失败。

> 本节所引为 Apple 官方文档的既有要求。本项目**没有** Intel 实机，
> 因此不对 Intel 上的实际表现做任何断言——只陈述该前置条件，并据此不声称支持。

### 8.2 脚本在 Intel 上的行为

`scripts/env.sh` 会检测 `uname -m` 并自动切换，无需手工改配置：

| | Apple 芯片（arm64） | Intel（x86_64） |
|---|---|---|
| `DM_ARCH` | `arm64` | `x86_64` |
| 图形后端 | `d3dmetal` | `wined3d` |
| `CX_ACTIVE_GRAPHICS_BACKEND` 等 | 设置（指向 D3DMetal） | **不设置** |
| `D3DM_SUPPORT_DXR` | 设置 | **不设置** |
| `ROSETTA_ADVERTISE_AVX` | 设置（走 Rosetta 必需） | **不设置**（原生 x86_64，AVX 本来就可用） |
| 引擎二进制 | 仍是同一个 x86_64 引擎（经 Rosetta） | 同一个引擎，**原生执行** |

注意引擎**不需要换**：它是 x86_64 Mach-O，在 Apple 芯片上经 Rosetta 2 跑，
在 Intel 上就是原生执行。

`scripts/status.sh` 增加了「〇、芯片架构」一节：

- Apple 芯片：检查 Rosetta 2 是否安装，并继续检查 D3DMetal 载荷
- Intel：直接说明 D4 为何跑不起来，并**跳过** D3DMetal 载荷检查
  （那里缺文件是预期行为，不应报成错误）

`scripts/run-d4.sh` 在 Intel 上启动前会打印同样的结论，避免让人白等。

### 8.3 Intel 上还有什么是有意义的

引擎本身、以及**条件 A（Agent caller authorization）**都不依赖 Metal——
它们只跟 Wine 的进程路径解析有关。所以：

- 战网客户端的安装、登录、下载游戏：在 Intel 上有机会工作
- 客户端界面显示：Intel Mac 有原生 OpenGL 驱动，`wined3d` 路径
  （即 Apple 芯片上我们会避开的那个后端）在 Intel 上反而是默认选择，
  有可能正常渲染
- **D4 本身：不行**（缺 DX12 能力）

如果你在 Intel 机器上试出了不同结果，欢迎反馈——但本仓库当前不声称支持。

### 8.4 排查 Intel 问题时的注意点

- **不要**因为看到 `d3d12check` 报 11_0 就怀疑装错了：Intel 上这是预期结果
- **不要**给 Intel 机器装 D3DMetal 载荷：它不仅没用，还可能与引擎的
  ABI 不匹配，引入新的加载失败（第二节 1.3 已记录 `__wine_unix_call` 未实现的失败模式）
- Intel 上不需要 Rosetta，也不需要 `ROSETTA_ADVERTISE_AVX`
