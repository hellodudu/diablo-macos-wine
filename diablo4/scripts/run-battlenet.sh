#!/bin/zsh
# 启动 Battle.net 客户端（用于登录、下载/更新 Diablo IV）
#
# ============ 这是经过实测才定下来的组合，四个要点缺一不可 ============
#  1. 引擎：$WINE（CX 26.3 GPL + D3DMetal）。试过 wine119/wined3d 跑客户端 → 会卡死。
#  2. 虚拟桌面：Wine 的 explorer 持有顶层窗口来合成 CEF 的无边框子窗口。
#     不用它 → 主窗口全黑；用了它 → 界面完整渲染。
#     代价：窗口尺寸固定、不可拖动缩放（由 DM_DESKTOP_SIZE 决定大小）。
#  3. WINE_CUSTOM_FRAME：抑制 macOS 在战网自绘的无边框窗口上再叠一层原生标题栏。
#  4. CEF 参数用 $BNET_CEF_ARGS，且必须【直启 Battle.net.exe】——
#     Battle.net Launcher.exe 只会转发前两个参数，后两个会被丢掉。
#
# 另外：直接执行 $WINE，不要经 arch/nohup（会剥掉 DYLD_*，界面无字体）。
set -u

HERE="${0:A:h}"
source "$HERE/env.sh"

# 每次启动前重打 Overlay 禁用（客户端自动更新会把它恢复回来）

if [ ! -f "$BNET_DIR_HOST/Battle.net.exe" ]; then
  print -r -- "Battle.net 尚未安装。先运行: $HERE/install-battlenet.sh"
  exit 1
fi

print -r -- "区域:   $DM_REGION_LABEL"
print -r -- "引擎:   $($WINE --version 2>/dev/null | head -1)"
print -r -- "前缀:   $WINEPREFIX"
if [ "$DM_USE_DESKTOP" = "1" ]; then
  print -r -- "虚拟桌面: ${DM_DESKTOP_NAME} ${DM_DESKTOP_SIZE}（窗口不可拖动缩放，改 DM_DESKTOP_SIZE 可调尺寸）"
else
  print -r -- "虚拟桌面: 已关闭（窗口可自由拖动缩放；若界面变黑就改回 DM_USE_DESKTOP=1）"
fi
print -r -- ""

if [ "$DM_USE_DESKTOP" = "1" ]; then
  # shellcheck disable=SC2086
  exec "$WINE" explorer "/desktop=${DM_DESKTOP_NAME},${DM_DESKTOP_SIZE}" "$BNET_EXE_WIN" ${=BNET_CEF_ARGS}
else
  # shellcheck disable=SC2086
  exec "$WINE" "$BNET_EXE_WIN" ${=BNET_CEF_ARGS}
fi
