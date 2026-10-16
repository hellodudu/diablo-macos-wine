# 《暗黑破坏神 IV》国服 在 Mac 上的共享环境配置（Apple 芯片 / Intel x86_64）
# 由 install-battlenet.sh / run-battlenet.sh / run-d4.sh / status.sh 共同读取
#
# ============================ 引擎为什么是它 ============================
# 要让 Battle.net + D4 同时跑起来，引擎必须同时满足两个条件，缺一不可：
#
#   条件 A：Agent caller authorization 能通过
#            → 需要 CodeWeavers 血统（macOS 上的 PID→路径解析）
#            GPTK 自带的 Wine 7.7（旧式 WoW64）会无限 401，实测几百次 0 成功
#
#   条件 B：DX12 到 feature level 12_0（D4 的硬要求）
#            → 需要 Apple 的 D3DMetal 载荷
#            Gcenx Wine 11.9 只有 MoltenVK+vkd3d，给到 11_0 就顶了
#
# 唯一同时满足的是：Soju 的 CX 引擎（由 CodeWeavers 26.3 公开发布的 GPL 源码构建）
#                   + 接入 Apple GPTK 的 D3DMetal 载荷
# 实测（Apple 芯片）：Agent 授权 0 失败；D3D12CreateDevice(12_0) 成功，最高特性级别 12_1
#
# ⚠️ Intel x86_64 的差别：Apple 官方 GPTK 要求 Apple 芯片，D3DMetal 因此不可用，
#    条件 B 无法满足 → D4 跑不起来。脚本在 Intel 上仍可正常工作并给出明确结论，
#    但本脚本不声称支持在 Intel 上运行 D4。见 docs/FINDINGS.md 第八节。
#
# ⚠️ 必须【直接】执行 $WINE，不要经 `arch -x86_64` 或 `nohup`：
#    它们是 Apple 签名的受限二进制，会把 DYLD_* 变量剥掉，导致
#    freetype/gnutls 加载失败（字体全无）。见 Soju README 的说明。
# ======================================================================

# ---- 区域 ----
export DM_REGION="${DM_REGION:-cn}"

# ---- 芯片架构检测（Apple 芯片 / Intel x86_64）----
# 两个架构的差别**不在脚本**，而在 Apple 的支持范围：
#   · Apple 官方 GPTK 的前置条件第一条是「A Mac with Apple silicon」，
#     而 D3DMetal（D4 所需的 DX12 唯一来源）来自 GPTK。
#   · 因此 Mac x86_64（Intel）上 **D4 本身跑不起来**——引擎可以跑、Agent 授权可以过，
#     但拿不到 DX12 feature level 12_0，D4 会在启动/渲染阶段失败。
# 本脚本在 Intel 上依然可以正确工作（不误判 Rosetta、给出明确结论、
# 跑的仍是同一个 x86_64 引擎，因为该引擎本身就是 x86_64 的），
# 但 **不声称支持在这类机器上运行 D4**。详见 docs/FINDINGS.md 第八节。
case "$(uname -m)" in
  arm64)  export DM_ARCH="arm64";  export DM_APPLE_SILICON=1 ;;
  x86_64) export DM_ARCH="x86_64"; export DM_APPLE_SILICON=0 ;;
  *)      export DM_ARCH="$(uname -m)"; export DM_APPLE_SILICON=0 ;;
esac

# ---- 引擎 ----
ENGINE="${SOJU_ENGINE:-$HOME/Games/d4/engine/cx-engine}"
export WINE="$ENGINE/bin/wine"
export WINESERVER="$ENGINE/bin/wineserver"
# 这一条是 freetype/gnutls 能找到的前提，不能省
export DYLD_FALLBACK_LIBRARY_PATH="$ENGINE/lib:/usr/lib"
export PATH="$ENGINE/bin:$PATH"

# ---- 双引擎分工（这是本项目第二个关键结构）----
# 同一个前缀、同一个 wine 版本，但换掉 d3d11 的实现来满足两边的不同需求：
#
#   客户端（Battle.net）：用【d3d11 = Wine 自带 wined3d】的引擎。
#       实测（进程确认存活后测量）：CEF 的 ANGLE 能成功建立 GL 上下文，
#       GLES3 失败 / kFatalFailure / SharedImageStub / GL disabled / GPU 进程退出 **全部为 0**。
#       而用带 D3DMetal 的引擎时这些各出现 9~12 次：ANGLE 会向 D3DMetal 的 DXGI 要它
#       没实现的 IDXGIResource → 合成失败 → 登录窗口（小面积）还能画，
#       **无边框的主窗口就是一片黑**。
#
#   游戏（D4）：用【带 D3DMetal】的引擎 → 才能拿到 DX12 feature level 12_1。
#
# 两个引擎版本同属 wine-11.x，共用同一个前缀。
export ENGINE_CLIENT="${SOJU_ENGINE_CLIENT:-$HOME/Games/battlenet-cn/wine119/Wine Staging.app/Contents/Resources/wine}"

# ---- 前缀与安装器按区域分流 ----
case "$DM_REGION" in
  cn)
    export WINEPREFIX="${WINEPREFIX:-$HOME/Games/d4/prefix-cx}"
    export BNET_INSTALLER="${BNET_INSTALLER:-$HOME/Games/battlenet-cn/installers/Battle.net-Setup-CN.exe}"
    export LANG=zh_CN.UTF-8
    export LC_ALL=zh_CN.UTF-8
    export DM_REGION_LABEL="国服 (Battle.net-Setup-CN.exe)"
    ;;
  intl)
    export WINEPREFIX="${WINEPREFIX:-$HOME/Games/d4/prefix-cx-intl}"
    export BNET_INSTALLER="${BNET_INSTALLER:-$HOME/Games/battlenet-cn/installers/Battle.net-Setup-enUS.exe}"
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export DM_REGION_LABEL="国际服 (enUS)"
    ;;
  *) printf '未知 DM_REGION: %s（应为 cn 或 intl）\n' "$DM_REGION" >&2; exit 1 ;;
esac
export WINEARCH=win64

# ---- 关键开关 ----
# ROSETTA_ADVERTISE_AVX：D4 加载器要求 AVX。Rosetta 2 支持 AVX，
#   但只有这个未公开变量才会对外声明。仅在 Apple 芯片（走 Rosetta）上需要；
#   Intel Mac 是原生 x86_64，AVX 本来就可用，设了也无害。
[ "$DM_APPLE_SILICON" = "1" ] && export ROSETTA_ADVERTISE_AVX=1

# ⚠️ 这一个不设，Battle.net 的登录界面就是黑屏 + 转圈，根本登不进去：
#   CEF 渲染进程调用 VirtualProtect 后会断言「旧保护 == PAGE_READWRITE」，
#   而纯 Wine 不做写时复制追踪，旧值永远是 PAGE_WRITECOPY(8) → int3 崩溃
#   （日志特征: Unhandled exception 0x80000003 ... address ...00E1，libcef.dll+0x16D00E1）
#   CrossOver 出货版默认开这个 hack，GPL 源码里只能靠这个环境变量打开。
export WINE_SIMULATE_WRITECOPY=1

# D3DM_SUPPORT_DXR：让 D3DMetal 暴露 DXR（光线追踪）能力，D4 用得到。仅 Apple 芯片有意义。
[ "$DM_APPLE_SILICON" = "1" ] && export D3DM_SUPPORT_DXR=1

# ---- 图形后端：按芯片架构自动选择 ----
# Apple 芯片：显式指定 D3DMetal（唯一能给到 DX12 FL 12_0 的路，D4 必需）。
#            不设这几个变量的话，CX 引擎不一定走 D3DMetal，可能退回
#            wined3d/vkd3d，那只到 DX12 FL 11_0。
# Intel x86_64：D3DMetal 不可用（Apple 官方 GPTK 要求 Apple 芯片），
#            因此这里不设 CX_* —— 引擎保持「无 GPTK 载荷」状态，
#            d3d11 由 Wine 自带 wined3d 提供。此时 Battle.net 客户端界面
#            可能仍能渲染（Intel Mac 有原生 OpenGL 驱动），但 **D4 无法运行**
#            （拿不到 DX12 FL 12_0）。详见 docs/FINDINGS.md 第八节。
if [ "$DM_APPLE_SILICON" = "1" ]; then
  export DM_GRAPHICS_BACKEND="d3dmetal"
  export CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal
  export CX_GRAPHICS_BACKEND=d3dmetal
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="$ENGINE/lib/external/libd3dshared.dylib"
else
  export DM_GRAPHICS_BACKEND="wined3d"
  unset CX_ACTIVE_GRAPHICS_BACKEND CX_GRAPHICS_BACKEND CX_APPLEGPTK_LIBD3DSHARED_PATH
fi

# ⚠️ 故意不设 WINEMSYNC=1。
#   Soju 的 play.sh 设了它，但实测在本机引擎上会把程序直接搞死（rc=1、零输出）：
#     基线（不设）           → rc=0，D3D12 FL 12_1
#     加 CX_* 后端           → rc=0，D3D12 FL 12_1
#     加 WINEMSYNC=1         → rc=1，无任何输出   ← 元凶
#   原因很可能是 msync 需要在 wineserver 启动时就协商，而现场已有非 msync 的
#   wineserver 在跑，客户端带上它就会不匹配。基线本来就全通，不必冒这个险。

# Overlay 用 DLL override 再压一层（双保险，重命名那套见 disable-overlay.sh）
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES,}winemenubuilder.exe=d"
export WINEDLLOVERRIDES="$WINEDLLOVERRIDES,gameoverlayrenderer,gameoverlayrenderer64=d"
export WINEDLLOVERRIDES="$WINEDLLOVERRIDES,battlenet.overlay.ui,battlenet.overlay.client.v1=d"

# ---- 自绘标题栏：抑制 macOS 原生标题栏 ----
# 战网的主窗口是**无边框、自绘**的。Mac 驱动看到 WS_CAPTION 就会叠一个 Cocoa 原生标题栏，
# 结果自绘的内容被挤到标题栏下面/错位 —— 实测症状就是主窗口里只有原生标题栏"战网"、
# 内容一片黑（登录窗口因为是普通带框窗口，所以反而正常）。
# 引擎里的 winemac 补丁提供 WINE_CUSTOM_FRAME（分号分隔的 exe 名列表）来关掉它，
# 与 Soju 为 GOG 的自绘标题栏所做的处理同源。
export WINE_CUSTOM_FRAME="Battle.net.exe;Battle.net Launcher.exe"

# ---- 虚拟桌面：让客户端界面能画出来的关键 ----
# 战网主窗口是**无边框**的，CEF 的内容要合成进这个窗口。实测：
#   不用虚拟桌面 → 登录窗口（普通带框）正常，主窗口全黑
#   用虚拟桌面   → 主窗口完整渲染（游戏列表 / 商城 / 安装按钮都正常）
# 代价：窗口由 Wine 的 explorer.exe 持有，尺寸固定、不可拖动缩放。
# 想换大小就改 DM_DESKTOP_SIZE（建议不超过屏幕逻辑分辨率）。
export DM_DESKTOP_SIZE="${DM_DESKTOP_SIZE:-1600x1000}"
export DM_DESKTOP_NAME="${DM_DESKTOP_NAME:-BattleNet}"
# 是否使用虚拟桌面。默认 1（界面能画出来的关键）。
#   代价：窗口由 explorer.exe 持有，是无边框 popup，macOS 层面无法拖动/缩放。
#   设 DM_USE_DESKTOP=0 可关掉它——那时窗口是普通 macOS 窗口，可自由拖动缩放，
#   但**有可能界面又变黑**（这正是当初启用虚拟桌面的原因）。
#   用法: DM_USE_DESKTOP=0 ~/Games/d4/run-battlenet.sh
export DM_USE_DESKTOP="${DM_USE_DESKTOP:-1}"
# 客户端要的 CEF 参数（必须直启 Battle.net.exe 才带得上，Launcher 会丢掉后两个）
export BNET_CEF_ARGS="--disable-gpu-compositing --from-launcher --in-process-gpu --use-gl=swiftshader"

# ---- 日志 ----
# ⚠️ 必须设。默认 WINEDEBUG 会让 wine 狂刷 fixme/trace，一次启动就能写出 21 GB 日志
export WINEDEBUG="${WINEDEBUG:--all,-fixme}"
export D4_LOG_DIR="$HOME/Games/d4/logs"
mkdir -p "$D4_LOG_DIR"

# ---- 游戏路径（Wine 内部路径）----
# ⚠️ 必须直接启动 Battle.net.exe，不要用 "Battle.net Launcher.exe"：
#   官方 Launcher 只转发前两个参数，而关键的 --in-process-gpu --use-gl=swiftshader
#   是 CrossOver 从它私有的加密兼容数据库（compatdb-26.dat）里、在 ntdll 内部注入的，
#   GPL 源码与二进制字符串里都没有 —— 自建引擎拿不到，后果就是登录界面全黑。
export BNET_EXE_WIN='C:\Program Files (x86)\Battle.net\Battle.net.exe'
export BNET_ARGS="--disable-gpu-compositing --from-launcher --in-process-gpu --use-gl=swiftshader"
# ⚠️ 必须是 Diablo IV.exe，不能是 Diablo IV Launcher.exe：
#   游戏靠 -sso 从战网客户端取令牌，Launcher 直接跑没有令牌会卡死在 MoltenVK 之后。
export D4_EXE_WIN='C:\Program Files (x86)\Diablo IV\Diablo IV.exe'
export BNET_DIR_HOST="$WINEPREFIX/drive_c/Program Files (x86)/Battle.net"
export D4_DIR_HOST="$WINEPREFIX/drive_c/Program Files (x86)/Diablo IV"
export AGENT_LOG_DIR="$WINEPREFIX/drive_c/ProgramData/Battle.net/Agent"
