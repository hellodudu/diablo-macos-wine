<div align="center">
  <img src="https://nie.res.netease.com/r/pic/20260416/7ea59a08-8843-4fcc-a522-e012380236fc.jpg" alt="暗黑破坏神 IV" width="100%">
</div>

# 在 Mac 上玩国服《暗黑破坏神 IV》

**用完全免费、完全开源的方式，让 Apple 芯片 Mac 跑起国服《暗黑破坏神 IV》。**

不用虚拟机，不用双系统，不用付费软件，**不涉及任何破解**。

---

## 这个项目解决的痛点

暴雪没有出过 macOS 版的《暗黑破坏神 IV》。Mac 用户想玩，只能靠兼容层去跑 Windows 版，
但现实是三条路都走不通：

| 你想的办法 | 实际结果 |
|---|---|
| 用免费兼容层（Whisky / 原生 GPTK / 各路免费 Wine 包） | 战网客户端无限重连登不进去，或者界面一片黑 |
| 自己折腾 Wine 配置 | 好不容易进了客户端，游戏一启动就退，或者卡在「正在登录」 |
| 买商业方案（CrossOver 等） | 能用，但要付费——而本项目的前提就是**不花钱、不破解** |

根子在于：D4 对运行环境有**四条硬要求**，而市面上**没有任何一个免费引擎同时满足**。
随便挑一个，都会正好缺其中一两条；失败方式还特别难懂——黑屏、闪退、没有报错。

**这个项目做的是：找到唯一一条同时满足四条的路，把它整理成可复现的脚本。**

---

## 四条硬要求，以及解法

| # | 硬要求 | 为什么免费方案通常过不去 | 我们的解法 |
|---|---|---|---|
| **A** | 战网 Agent 要校验连接进程的身份 | 原生 GPTK 的 Wine 会无限 401 重连（macOS 没有 `/proc`，进程路径解析不出来） | 用 **CodeWeavers 血统**的 Wine 引擎 |
| **B** | D4 需要 **DX12 feature level 12_0** | 普通 Wine 只有 MoltenVK + vkd3d，到 11_0 就顶了 | 接入 **Apple D3DMetal** |
| **C** | 战网客户端（Chromium 界面）要能显示 | 默认配置下主窗口**全黑**——它是无边框窗口，内容合成不进去 | 指定渲染方式 + 用 Wine 虚拟桌面提供合成载体 |
| **D** | 游戏要能真正启动 | 战网的 Overlay 组件会卡死游戏的登录初始化 | 绕开客户端，直接启动游戏本体 |

关键在于：**A 和 B 来自两个不同来源，必须拼在一起**——这正是现成引擎都不行的原因。

```
CodeWeavers 血统的 Wine 引擎（解决 A）
        +
Apple D3DMetal（解决 B）
        ↓
唯一能跑国服 D4 的免费方案
```

两者的获取都完全合法：前者由 **CodeWeavers 公开发布的 GPL 源码**构建，
后者是 **Apple 免费提供的 Game Porting Toolkit**。

---

## 成果

| 项目 | 状态 |
|---|---|
| 国服《暗黑破坏神 IV》 | ✅ **可正常游玩**——联网登录、图形与音频正常 |
| 全程费用 | **0 元**，未使用任何付费产品或付费试用 |

---

## 用到了哪些组件

| 组件 | 用途 | 许可 / 获取方式 |
|---|---|---|
| **Wine**（CodeWeavers 26.3 公开源码） | 运行 Windows 程序的核心 | GPL · [CodeWeavers 源码站](https://media.codeweavers.com/pub/crossover/source/) |
| **Apple Game Porting Toolkit** | 提供 D3DMetal（DX12 → Metal） | Apple 免费下载 · [开发者页面](https://developer.apple.com/games/game-porting-toolkit/) |
| **Rosetta 2** | Apple 芯片上执行 x86_64 代码 | Apple 系统组件，免费 |
| **MoltenVK** | Vulkan → Metal（引擎自带） | Apache-2.0 |
| **mingw-w64** | 编译本仓库的诊断工具 | 开源 |

> 引擎由上述 **GPL 源码**构建，或使用社区基于同一份源码的预编译版（如
> [Soju](https://github.com/BCD1210/soju)）。**本仓库不包含任何第三方二进制。**

---

## 环境要求

| | 要求 |
|---|---|
| 芯片 | **Apple 芯片**（M1 或更新） |
| 系统 | macOS 26 或更新 |
| 磁盘 | 游戏本体约 **90 GB** |
| 其他 | Rosetta 2、Apple Game Porting Toolkit（均免费） |
| 游戏 | **你自己合法拥有的国服《暗黑破坏神 IV》**，以及已绑定网易通行证的国服战网账号 |

### 关于 Intel Mac

脚本支持在 Intel（x86_64）Mac 上运行——会自动识别架构、跳过 Rosetta 相关设置、
改用 Wine 自带的图形后端。**但 D4 本身在 Intel Mac 上跑不起来**：
D4 需要的 DX12 能力来自 Apple 的 D3DMetal，而 Apple 官方 GPTK 的前置条件明确要求
「A Mac with Apple silicon」。这属于 Apple 的支持范围，不是脚本能绕过的。

脚本在这种情况下会直接告诉你原因，不会让你白等。

---

## 快速开始

```bash
# 1. 准备引擎（组装步骤见 diablo4/docs/FINDINGS.md 第一节）
# 2. 改配置
$EDITOR diablo4/scripts/env.sh

# 3. 装战网客户端并登录（凭据由你本人输入）
diablo4/scripts/install-battlenet.sh
diablo4/scripts/run-battlenet.sh

# 4. 在客户端里安装游戏

# 5. 启动游戏（客户端需保持运行，它负责提供登录令牌）
diablo4/scripts/run-d4.sh

# 随时体检
diablo4/scripts/status.sh
```

`status.sh` 会逐条检查四个条件，并直接告诉你哪一条没过、为什么。

---

## 关于合法性（请务必阅读）

**本项目不涉及任何破解或盗版行为。** 具体来说：

- ✅ **你需要自己拥有游戏。** 本项目帮你让**官方客户端**在 Mac 上正常运行，
  但不提供、不包含、不引导获取任何游戏文件。
- ✅ **不含任何游戏内容。** 本仓库只有脚本和文档，没有一行游戏代码、一张美术资源。
- ✅ **不修改游戏、不绕过授权、不提供序列号。** 登录仍由战网官方服务器验证，
  账号与授权状态不变——你玩的还是那个官方正版游戏。
- ✅ **不使用任何破解工具，也不使用付费产品的盗版。**
- ✅ 所用组件均为**公开发布的 GPL 源码**或**官方免费下载**的工具。

本项目与暴雪娱乐、网易均无关联，未获其背书或赞助。
文中提及的游戏名称与商标归其各自权利人所有。

**请在 issue 与 PR 中遵守这一点**：不要粘贴游戏文件，也不要讨论获取渠道。

---

## 已知限制

| 限制 | 说明 |
|---|---|
| 客户端窗口不可拖动缩放 | 客户端跑在 Wine 虚拟桌面里（这正是界面能显示的代价）。尺寸可用 `DM_DESKTOP_SIZE` 调整 |
| Intel Mac 无法运行游戏 | 见上文「关于 Intel Mac」 |
| 首次启动较慢 | 首次运行需编译着色器，CPU 会满载数分钟，属正常现象 |
| 需要自己准备引擎 | 分发第三方二进制既不合规也不安全，因此本仓库只提供脚本 |

---

## 目录结构

```
.
├── README.md                      ← 你在这里
├── LICENSE
└── diablo4/
    ├── README.md                  ← 操作手册
    ├── docs/
    │   ├── FINDINGS.md            ← 技术细节：四条要求的原理、引擎组装、实测数据
    │   └── verification-2026-10-16.txt   ← 实测原始输出
    ├── scripts/
    │   ├── env.sh                 ← 唯一配置入口（含架构自动识别）
    │   ├── run-battlenet.sh       ← 启动客户端
    │   ├── run-d4.sh              ← 启动游戏
    │   ├── install-battlenet.sh   ← 跑官方安装器
    │   ├── status.sh              ← 逐条体检四个条件
    │   └── disable-overlay.sh     ← 应急用（默认拒绝执行，见文件头警告）
    └── tools/                     ← 诊断工具（C 源码，自行编译）
```

想深入了解原理、踩过的坑、以及如何自己拼出这个引擎，见
**[diablo4/docs/FINDINGS.md](diablo4/docs/FINDINGS.md)**。

---

## 致谢

- **[Soju](https://github.com/BCD1210/soju)** —— 本项目的引擎与大量排查思路来自它。
  其作者从 CodeWeavers 公开发布的 GPL 源码构建引擎，并把每一个坑都写成了文档。
- **[CodeWeavers](https://www.codeweavers.com/)** —— CrossOver 的 Wine 源码以 GPL 发布。
- **[Apple](https://developer.apple.com/games/game-porting-toolkit/)** —— Game Porting Toolkit / D3DMetal。
- **mingw-w64**、**MoltenVK** 及所有上游开源项目。

---

## 许可

本仓库的脚本与文档：[MIT](LICENSE)。
第三方组件（引擎、Apple GPTK、MoltenVK 等）各自遵循其原始许可。

<sub>头图：官方宣传素材，版权归 Blizzard Entertainment / 网易所有，此处仅作引用示意。</sub>
