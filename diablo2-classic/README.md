# 经典版《暗黑破坏神 II》环境

> 本目录是 [主仓库](../README.md) 的经典 D2 部分，脚本在 `scripts/`。
> 与国服 D4 不同，经典版**不需要战网启动器**，单机与局域网功能完整。

本目录是为在一台 Apple M5 Pro / macOS 26.6.2 上运行**经典版 Diablo II（1.14d，含毁灭之王）**搭建的。
之所以是经典版而不是 D2R：经典版是独立程序，**不需要 Battle.net 启动器**，单机、局域网 TCP-IP 全功能，
1.12 之后也不再需要光盘。D2R 是另一回事（见文末）。

> ⚠️ 本环境**不包含任何游戏文件**。你需要自己拥有并安装游戏。
> 安装器从暴雪官方页面下载：<https://us.support.blizzard.com/en/help/article/13867>

---

## 一、已经搭好并验证过的东西

| 项目 | 位置 | 状态 |
|---|---|---|
| Wine 引擎 | `/Applications/Game Porting Toolkit.app/.../wine/bin/wine64` | wine-7.7，Apple 官方 GPTK |
| 专用 Wine 前缀 | `~/Games/diablo2/prefix`（329 MB） | 已创建，已初始化 |
| 双击启动器 | `~/Applications/Diablo II.app` | 已生成，可双击 |
| 32 位 DirectDraw / D3D / OpenGL 实测程序 | `tools/d2check32.exe`（源码 `tools/d2check.c`） | **实跑全部通过**，见 `tools/verification-2026-10-15.txt` |
| Glide 3D 包装器 | `staging/glide3x.dll` 等（Sven's Glide Wrapper 1.4e，免费软件） | 已下载待用 |
| Porting Kit 6.7.0 | `/Applications/Porting Kit.app` | 已安装（arm64、已公证、校验和与官方一致） |

### 实测结论（关键）

在 Wine 里的真实测量结果：

- **32 位 WoW64 可用**：32 位 PE 进程正常启动，`%PROCESSOR_ARCHITECTURE%` = `x86`
- **DirectDraw 整条 2D 路径可用**：对象创建、主表面、离屏表面、Clipper、Lock、GetDC 全部成功
- **d3d8 / d3d9 可加载**，`Direct3DCreate9` 成功
- **OpenGL 可用**：`GL_VERSION = 2.1 Metal - 90.5`，`GL_RENDERER = Apple M5 Pro`

也就是说：D2 的 2D 模式（DirectDraw）和 3D 模式所需的 OpenGL（Sven's Glide Wrapper 走的路径）**都具备条件**。

---

## 二、拿到安装器之后怎么做

### 第 1 步：下载 Blizzard 官方安装器

到 <https://us.support.blizzard.com/en/help/article/13867> 下载：

- 《暗黑破坏神 II》本体安装器
- 《毁灭之王》(Lord of Destruction) 安装器

两个都要。需要你的战网账号已绑定该游戏，安装时会要求输入 16 位 CD key。

### 第 2 步：运行安装器

```bash
~/Games/diablo2/install-game.sh
```

脚本会自动在 `~/Downloads`、`staging/`、本目录里找安装器，列出让你选，然后丢给 Wine 运行。
安装路径**保持默认**（`C:\Program Files (x86)\Diablo II`）即可。

### 第 3 步：启动

直接双击 **`~/Applications/Diablo II.app`**（Finder 侧边栏「应用程序」里也能看到）。

### 第 4 步（可选）：开启 3D 透视模式

```bash
~/Games/diablo2/setup-glide.sh     # 把 glide3x.dll 装进游戏目录
```

然后把 `config.env` 里的 `DM_GLIDE` 从 `0` 改成 `1`，或者直接跑 `./run-game.sh -3dfx`。
3D 模式画质更好；如果画面异常，改回 `0` 用 2D 模式（2D 最稳）。

---

## 三、配置：`config.env`

出问题时先改这里，不用动脚本。

| 变量 | 默认 | 说明 |
|---|---|---|
| `DM_WINE_BIN` | GPTK 的 wine64 | 换引擎就改这里（例如 kegworks / Gcenx wine-stable） |
| `DM_ARGS` | `-w` | `-w` = 窗口模式，**在 Wine 下最稳，建议先用**。留空 = 全屏 |
| `DM_VIRTUAL_DESKTOP` | 空 | 设成 `800x600` 用 Wine 虚拟桌面跑，老游戏全屏切换出问题时用它 |
| `DM_GLIDE` | `0` | 改成 `1` 用 `-3dfx`（Glide 3D）启动 |
| `DM_AUDIO_DRIVER` | 空 | 声音异常时试 `coreaudio` |
| `DM_LOG` | `~/Games/diablo2/wine.log` | 启动日志，排错先看它 |

---

## 四、自检与排错

```bash
~/Games/diablo2/doctor.sh                    # 环境逐项体检（只读）
~/Games/diablo2/tools/d2check32.exe          # 重跑底层兼容性实测
tail -50 ~/Games/diablo2/wine.log            # 看启动日志
```

常见情况：

| 现象 | 处理 |
|---|---|
| 双击 App 弹「还没有安装游戏」 | 还没装，先跑 `install-game.sh` |
| 黑屏 / 花屏 | `DM_ARGS="-w"` 窗口模式；再不行设 `DM_VIRTUAL_DESKTOP="800x600"` |
| 全屏切换把桌面搞乱 | 用 `-w` 窗口模式，或设虚拟桌面 |
| 没声音 | `DM_AUDIO_DRIVER="coreaudio"` |
| 3D 模式起不来 | `DM_GLIDE=0` 回 2D；3D 需要先跑 `setup-glide.sh` |
| 想重开一个干净前缀 | 备份后删掉 `prefix/`，重新执行 `wineboot --init` |

---

## 五、另外两条路线

### A. Porting Kit（GUI，社区验证过的流程）

`/Applications/Porting Kit.app` 已装好。它的社区安装器就是网上那份经典 D2 教程用的路径：

1. 打开 Porting Kit → 新建应用 → 搜 **Diablo 2** → 用它的社区安装器
2. 再新建 **Diablo 2 Lord of Destruction** → 同样走社区安装器
3. 想开 3D：把 `~/Games/diablo2/staging/` 里的 `glide3x.dll` 等 4 个文件
   拷进包裹里的 `Program Files (x86)/Diablo II`
4. 在该应用的 Advanced 里把启动目标改成
   `C:\Program Files (x86)\Diablo II\Diablo II.exe -3dfx`

适合「不想碰命令行、想要 GUI 管理」的情况。两条路线用的是各自独立的 Wine 前缀，不会互相干扰。

### B. CrossOver（付费，$74/年）

兼容性最好、最省心，但它要付费。你也已经有一个空的 `~/Applications/CrossOver` 目录，
装了之后按上面同样的思路配即可。不强求。

---

## 六、诚实的边界：已验证 vs 未验证

**已验证（本机实测）**

- 32 位 WoW64 运行 ✅
- DirectDraw 2D 全路径 ✅
- OpenGL 上下文与渲染调用 ✅
- d3d8 / d3d9 加载 ✅

**未验证（等你有游戏文件才能测）**

- Blizzard 安装器在 Wine 下的实际表现（安装界面、CD key 输入）
- 游戏本体启动、存档、音频、输入
- **全屏模式下的显示模式切换**——这是唯一有真实风险的路径，
  所以默认给你配了 `-w` 窗口模式，并提供了虚拟桌面选项；窗口模式最稳
- Glide 3D 模式在真实游戏下的表现

---

## 七、卸载

```bash
rm -rf ~/Applications/"Diablo II.app"      # 启动器
rm -rf ~/Games/diablo2                     # 前缀、脚本、包装器、日志
rm -rf "/Applications/Porting Kit.app"     # 如果不需要 GUI 路线
brew uninstall mingw-w64                   # 如果不需要那个实测程序自己重编
```

（`mingw-w64` 只是为了让 `tools/d2check.c` 能编译成 32 位 exe，游戏本身不需要它。）
