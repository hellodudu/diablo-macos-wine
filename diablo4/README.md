# 国服《暗黑破坏神 IV》操作手册

> 本目录是 [主仓库](../README.md) 的 D4 部分。脚本已按仓库结构放在 `scripts/`，
> 直接运行前请先按 `scripts/env.sh` 里的注释确认引擎路径。
> 四个条件的**原理与实测数据**见 [docs/FINDINGS.md](docs/FINDINGS.md)。

目标：在本机（M5 Pro / macOS 26.6.2 / arm64）完成**国服** D4 的安装，使其能启动并登录进入游戏。

**硬性约束（用户规则）**：只用免费 / 开源方案，**不使用 CrossOver 等付费产品**。
登录凭据由用户本人输入，agent 不接触账号密码。

> ✅ **当前状态：四个条件的技术前提已全部打通并逐项实测。** 国服 Battle.net 已安装并运行，
> 客户端已连接到 **`region=CN`**（登录页 `account.battlenet.com.cn`，HTTP 200），
> Overlay 已禁用、D4 加载器依赖已核验。**只差你登录，然后在客户端里安装 D4。**

---

## 一、核心结论：引擎与环境必须同时满足四个条件

D4 要跑到"能进游戏"，这台机器上得同时过四关。市面上的免费引擎**没有一个原生满足**，这是你这几个月反复失败的根本原因。

| 条件 | 为什么需要 | GPTK Wine 7.7 | Gcenx Wine 11.9 | **CX 26.3 GPL + D3DMetal** |
|---|---|---|---|---|
| **A. Agent 授权** | Battle.net 的 Agent 要校验连接进程的身份 | ❌ 无限 401 | ✅ 0 失败 | ✅ **0 失败** |
| **B. DX12 FL 12_0** | D4 是 DX12 游戏，硬要求 | ✅ 12_0 | ❌ 只有 11_0 | ✅ **12_1** |
| **C. 登录界面能渲染** | 客户端是 CEF（Chromium）界面；**两层原因**：渲染器崩溃 + 启动参数缺失 | ❌ 渲染器崩溃 | ? | ✅ **页 200 且 GPU 进程 0** |
| **D. D4 启动前提** | 加载器硬查 `FindNextFileNameW`；Overlay 注入会卡死登录 | ❌ | ❌ | ✅ **两项均已处理** |

### 条件 D：D4 启动前提（2026-10-15 实测）

两条独立的东西，任一条不满足 D4 都进不去：

**(1) `kernel32.FindNextFileNameW` 必须存在。**
2026 年 5 月 D4 更新后，`diablo_iv_loader.dll` 会**硬性查询**这个 kernel32 导出；当时 Wine 没有它，
导致 Linux/Wine 用户**完全无法启动**（[暴雪论坛该帖 600+ 楼](https://us.forums.blizzard.com/en/d4/t/unable-to-play-on-linux-platforms-after-new-update/260312/615)）。
上游后来补了 stub，Proton 也修了。本机实测（自编 `tools/loadercheck.c`）：

```
[ OK ]  kernel32.FindFirstFileNameW 存在
[ OK ]  kernel32.FindNextFileNameW 存在
[ OK ]  FindNextFileNameW 运行时可解析
[ OK ]  用无效句柄调用返回 FALSE（err=120）—— 行为正确，非崩溃
```

`err=120` = `ERROR_CALL_NOT_IMPLEMENTED`，即它是**stub**。这与上游的修法一致（社区结论就是"加 stub 即可"），
加载器只做存在性检查，不依赖返回值。

**(2) Battle.net Overlay 必须禁用。**
[CrossOver 中文官网 2026-07-27 的文档](https://www.crossoverchina.com/faq/cross-ahpls.html)记录了国服 D4 的确切症状与解法：

> 2026 年 5 月更新后 Mac 用户无法登录，**卡在「正在登录《暗黑破坏神IV》」，且无法正常关闭，只能强制退出**。
> 原因是**战网 Overlay 组件在 Wine 环境下注入 D4 时卡住了登录后的初始化流程**。解法是重命名 Overlay 文件。

本机对应文件在 `…/Battle.net/Battle.net.17932/bdk/`，共三个：

| 文件 | 处理 |
|---|---|
| `battlenet.overlay.runtime.exe` | → `.disabled` |
| `battlenet.overlay.ui.dll` | → `.disabled` |
| `battlenet.overlay.client.v1.dll` | → `.disabled` |

⚠️ **战网客户端每次自动更新都会把这些文件恢复回来**，所以 `disable-overlay.sh` 是幂等的，
并被 `run-battlenet.sh` / `run-d4.sh` 在启动前自动调用。这条很容易被忽略，
但它是"能登录"和"卡在正在登录"的分界线。

### 条件 C：登录界面黑屏的两层原因（2026-10-15 实测确诊）

条件 C 其实是**两个独立的问题**，症状都是"黑屏"，但根因和修法完全不同。缺任何一个都是黑屏。

#### C-1：CEF 渲染器 int3 崩溃 → 需要 `WINE_SIMULATE_WRITECOPY=1`

症状：CEF 渲染进程反复重启。日志特征：

```
wine: Unhandled exception 0x80000003 in thread 340 at address 68FA00E1
```

`0x80000003` = `EXCEPTION_BREAKPOINT`；地址尾部 `00E1` 与已知的 `libcef.dll+0x16D00E1` 一致。

根因：CEF 渲染器调用 `VirtualProtect` 后断言「旧保护 == `PAGE_READWRITE`」，
而**纯 Wine 不追踪写时复制**，镜像页的旧值永远是 `PAGE_WRITECOPY(8)` → 断言失败 → int3 崩溃。
CrossOver 出货版默认开启这个 hack（CW Hack 22996），而 **GPL 源码里只能靠环境变量打开**：

```sh
export WINE_SIMULATE_WRITECOPY=1      # ← 已写进 env.sh，非可选
```

#### C-2：画面全黑（渲染器不崩、页面 200，但什么都没画出来）→ 需要正确的启动参数

这一层更隐蔽：**渲染器活着、页面 `statusCode=200`、没有任何异常，但内容区全黑**，
只有标题栏和 Blizzard logo（那是客户端自己的 UI）能画出来。2026-10-15 用户实测截图确认过一次。

根因（来自 Soju 的 `docs/DIAGNOSIS.md`）：CrossOver 出货版会从它**私有的加密兼容数据库**
（`compatdb-26.dat` + `cxcompatdb.so`）里、在 ntdll 的 `NtCreateUserProcess` **内部**注入两个参数：

```
--in-process-gpu --use-gl=swiftshader
```

而 `Battle.net Launcher.exe` **只转发前两个参数**（`--disable-gpu-compositing --from-launcher`），
后两个从不透传。这两个参数在 GPL 源码里没有、在二进制字符串里也搜不到 ——
所以**任何自建引擎都拿不到它们**。缺了它们的后果：CEF 另起一个独立的 GPU 进程，
该进程初始化失败（`Exiting GPU process due to errors` ×9）→ `GL is disabled` → 什么都不合成 → **全黑**。

修法：**不要经过 `Battle.net Launcher.exe`**，直接启动 `Battle.net.exe` 并补上全部四个参数（已写进 `env.sh`）：

```sh
BNET_EXE_WIN='C:\Program Files (x86)\Battle.net\Battle.net.exe'
BNET_ARGS="--disable-gpu-compositing --from-launcher --in-process-gpu --use-gl=swiftshader"
```

验证判据（Soju 记录的成功状态与本节实测一致）：

| 判据 | 黑屏时 | 修好后 |
|---|---|---|
| Battle.net 的 `--type=gpu-process` 进程数 | 有 | **0** |
| 渲染器命令行是否含 `--in-process-gpu` | 否 | **是** |
| `Exiting GPU process due to errors` | ×9 | **0** |
| 渲染进程被终止 | 有 | **0** |
| 登录页 | — | **`finished loading. statusCode=200`** |

> 注意：日志里 `SharedImageStub: unable to create context`、
> `Failed to create GLES3 context`、`WSALookupServiceBegin failed` 这几条是**无害的** ——
> 真正的 CrossOver 出货版同样会刷这些（Soju 原话：GL 에러는 무해，진짜 CrossOver도 99개씩 냄）。

> 你 5 月的脚本里已经设过 `WINE_SIMULATE_WRITECOPY=1`（`fix-agent-401-exp.sh`、
> `install-battlenet-cn.sh` 等），说明 C-1 你当时摸索到了；C-2 那四个参数则无法通过脚本获得，
> 只能靠直启绕开 Launcher。

### 条件 A 的根因（已定证）

Agent 日志：

```
[I] Unable to validate connecting process
[E] Failed Caller authorization due to signature for 'Battle.net.exe'
    -> Agent init returned status code=401
```

排查过程（三个猜测全部被实测否定）：

| 猜测 | 实测 |
|---|---|
| 缺 `ntlm_auth` | ❌ 只是警告，非 401 来源 |
| Windows 版本不够（注册表 6.3） | ❌ `RtlGetVersion` 一直是 10.x |
| 签名验证能力不足 | ❌ 自编 `tools/sigcheck.c` 传正确路径时 `WinVerifyTrust` 返回 **0** |

真凶在你那次 274 MB 调试日志里：

```
WinVerifyTrust returning 00000002   ← 58 次
```

`0x00000002` = `ERROR_FILE_NOT_FOUND`。**Agent 拿 PID 解析不出可执行文件的路径**，签名校验必然失败。
macOS 没有 `/proc`，这需要 Wine 里有专门代码路径 —— 也就是 CodeWeavers 血统的引擎才有。

历史证据：你四次尝试（`battle-net`、`prefix`、`prefix-wine11`、`prefix-scotch`）累计数百次
`Failed Caller authorization`，**成功授权 0 次**。GPTK 下的 `Battle.net.exe` 本身就失败 2557+ 次，
所以"用 GPTK 渲染 + 别处装"的混合方案不成立。

### 条件 B 的实测

自编 `tools/d3d12check.c`：

```
Gcenx Wine 11.9（MoltenVK + vkd3d）:  D3D12CreateDevice(12_0) FAILED hr=0x80070057，只有 11_0
CX 26.3 GPL + Apple D3DMetal:        D3D12CreateDevice(12_0) 成功，最高特性级别 12_1  ✅
```

**一个重要否定结论**：D3DMetal **不能靠拷文件接进 Gcenx Wine 11.9**。实测报
`unimplemented function ntdll.dll.__wine_unix_call` → `d3d12.dll failed to initialize`。
Apple 的垫片要求引擎侧 ABI 匹配，必须用 CodeWeavers 血统的引擎。

## 二、解决方案（全部免费）

**引擎**：`~/Games/d4/engine/cx-engine`（1.9 GB，`wine-11.0`）
来源：Soju 的 `engine-v1.5/wine-engine-x86_64.tar.xz`（366 MB，GPL）
它由 **CodeWeavers 26.3 公开发布的 GPL 源码**构建 —— 用的是公开源码，不是付费产品。

**D3DMetal 载荷**：从你本地已有的 GPTK 3.0-3 接入，三部分缺一不可：

| 部分 | 内容 |
|---|---|
| 1 | `lib/external/`（`D3DMetal.framework` + `libd3dshared.dylib`） |
| 2 | Apple 的 PE 垫片 `d3d11/d3d12/dxgi/d3d10/atidxx64/nvapi64/nvngx*.dll`（特征串 `D3DMetalDLLsBase`） |
| 3 | `lib/wine/x86_64-unix/<name>.so` 作为 **symlink** 指向 `../../external/libd3dshared.dylib`（拷成实体文件会破坏 `@loader_path` 解析） |

**⚠️ 必须【直接】执行 `$WINE`，不要经 `arch -x86_64` 或 `nohup`**：它们是 Apple 签名的受限二进制，
会把 `DYLD_*` 变量剥掉，导致 freetype/gnutls 加载失败（字体全无）。这条踩过，已在 `env.sh` 里注明。

## 三、关于国服的三个事实

1. **国服客户端不是另一个构建。** 实测：`Battle.net-Setup-CN.exe` 与 `Battle.net-Setup-enUS.exe`
   装出来的 `Battle.net.exe` **逐字节相同**（`171d749cf2d6`）。国服是**登录时选定的区域**。
   你原来那个 `Battle.net-Setup-zhCN.exe` 只是国际版中文包（不含 `cn.version.battlenet.com.cn`），
   已改名为 `...intl-zhCN.misnamed.exe` 以免误用。
2. **免费领取活动已截止。** 国服基础版本体原价 128 元，限时免费领取期为
   **2026-04-28 至 2026-08-04**；今天 10-15，**已过期**。除非活动期内领过，否则需在国服商店购买。
3. **国服需要国服战网账号并绑定网易通行证；国服与国际服数据不互通。**

## 四、接下来做什么

```bash
~/Games/d4/run-battlenet.sh      # 打开国服 Battle.net（此刻应已在运行，登录页指向 account.battlenet.com.cn）
# → 你登录，然后在客户端里安装 Diablo IV
~/Games/d4/run-d4.sh             # 装完后启动游戏
~/Games/d4/status.sh             # 随时体检（会同时校验条件 A 和 B）
```

或双击 `~/Applications/Diablo IV.app`。

切国际服：`DM_REGION=intl ~/Games/d4/run-battlenet.sh`（前缀独立，可共存）。

## 五、下一步的风险与已知项

| 项 | 状态 |
|---|---|
| Agent 授权 | ✅ 实测 0 失败 |
| DX12 FL 12_0 | ✅ 实测 12_1 |
| 客户端连接 CN 区域 | ✅ 日志 `region=CN`，正在取 `catalogs region=cn` 补丁元数据 |
| 反作弊（Warden） | ⚠️ 未验证。Wine 下能否通过由游戏启动时决定，风险自评 |
| D4 实际渲染 | ⏸ 待安装后验证（D3DMetal 与 D4 的组合是社区已验证过的方向） |

## 六、关键环境变量（`env.sh` 里）

| 变量 | 作用 |
|---|---|
| `SOJU_ENGINE` | 引擎路径，默认 `~/Games/d4/engine/cx-engine` |
| `DYLD_FALLBACK_LIBRARY_PATH` | **必须**，否则 freetype/gnutls 找不到 |
| `WINE_SIMULATE_WRITECOPY=1` | **必须**，条件 C-1：缺了 CEF 渲染器 int3 崩溃 |
| `BNET_ARGS` | **必须**，条件 C-2：`--disable-gpu-compositing --from-launcher --in-process-gpu --use-gl=swiftshader`。必须**直启 `Battle.net.exe`**，经 `Battle.net Launcher.exe` 会丢掉后两个参数 → 画面全黑 |
| `ROSETTA_ADVERTISE_AVX=1` | D4 加载器要求 AVX；Rosetta 2 支持，但只有这个未公开变量才会对外声明。缺了会卡在图形初始化前（约 86 MB 内存、0% CPU） |
| `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`、`CX_GRAPHICS_BACKEND=d3dmetal` | 显式指定走 D3DMetal 后端，避免退回 wined3d/vkd3d（那只到 FL 11_0） |
| `CX_APPLEGPTK_LIBD3DSHARED_PATH` | 显式指定 `libd3dshared.dylib` 路径 |
| `D3DM_SUPPORT_DXR=1` | 让 D3DMetal 暴露 DXR |
| `WINEDEBUG=-all,-fixme` | **必须**，否则默认调试输出会写出 21 GB 日志 |
| `DM_REGION` | `cn`（默认，国服）/ `intl` |

### ⚠️ 一个故意不设的变量：`WINEMSYNC`

Soju 的 `play.sh` 设了 `WINEMSYNC=1`，但**实测在本机引擎上会把程序直接搞死**（rc=1、零输出）。
对照实验结果：

| 配置 | 结果 |
|---|---|
| 基线（不设） | ✅ rc=0，D3D12 FL **12_1** |
| 加 `CX_*` 后端变量 | ✅ rc=0，D3D12 FL **12_1** |
| **加 `WINEMSYNC=1`** | ❌ **rc=1，无任何输出** |

推测原因是 msync 需要在 `wineserver` 启动时就协商，而现场已有非 msync 的服务在跑，客户端带上它就不匹配。
基线本来就全通，所以**刻意不设**它 —— 照抄别人的配方反而会引入回归。

## 七、文件与目录

| 路径 | 说明 |
|---|---|
| `env.sh` | 共享配置 —— **改配置只改这里** |
| `install-battlenet.sh` | 跑官方安装器（按 `DM_REGION` 选包） |
| `run-battlenet.sh` / `run-d4.sh` | 启动客户端 / 游戏（均已去掉 `arch`，且启动前自动重打 Overlay 禁用） |
| `disable-overlay.sh` | 禁用战网 Overlay（幂等；客户端更新会恢复，故每次启动自动调用） |
| `status.sh` | 体检，逐条验证条件 A / B / C / D |
| `engine/cx-engine/` | CX 26.3 GPL 引擎 + 已接入的 D3DMetal（1.9 GB） |
| `engine/wine-engine-x86_64.tar.xz` | 引擎原始包（367 MB，可删） |
| `prefix-cx/` | 国服前缀（2.3 GB） |
| `prefix-cn/`、`cn-prefix/`、`wine119-prefix/` | ⚠️ 过程中的旧前缀（Wine 11.9），可删，共约 4.5 GB |
| `tools/sigcheck.c` | 签名验证能力测试（条件 A 定证用） |
| `tools/vercheck.c` | 系统版本权威测试 |
| `tools/d3d12check.c` | DX12 能力实测（条件 B 定证用） |
| `tools/loadercheck.c` | D4 加载器依赖核验（条件 D 定证用） |
| `setup-prefix.sh` | ⚠️ 已过时（GPTK 时代产物） |
| `logs/` | 各次运行日志 |
