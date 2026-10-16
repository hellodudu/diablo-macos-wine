#!/bin/bash
# 环境自检：逐项报告这台机器能不能跑经典版 Diablo II，以及还缺什么。
# 只读检查，不修改任何东西。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.env"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
note() { printf '  \033[33m·\033[0m %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

echo "Diablo II on macOS 环境自检"
echo "路径: $HERE"

head_ "一、引擎"
if [ -x "$DM_WINE_BIN" ]; then
  ok "Wine 引擎存在: $DM_WINE_BIN"
  ver="$("$DM_WINE_BIN" --version 2>/dev/null | head -1)"
  [ -n "$ver" ] && ok "版本: $ver"
else
  bad "找不到 Wine 引擎: $DM_WINE_BIN"
  note "安装 Apple Game Porting Toolkit，或修改 config.env 里的 DM_WINE_BIN"
fi

head_ "二、Rosetta 2（Apple 芯片运行 x86-64 代码必需）"
if arch -x86_64 /bin/echo ok >/dev/null 2>&1; then ok "Rosetta 2 可用"
else bad "Rosetta 2 不可用，执行: softwareupdate --install-rosetta"; fi

head_ "三、Wine 前缀"
if [ -d "$DM_PREFIX" ]; then
  ok "前缀存在: $DM_PREFIX"
  sz="$(du -sh "$DM_PREFIX" 2>/dev/null | cut -f1)"
  ok "占用空间: ${sz:-未知}"
  # 32 位支持：WoW64 模块是否就位
  if [ -f "$DM_PREFIX/drive_c/windows/syswow64/cmd.exe" ]; then
    arch_info="$("$DM_WINE_BIN" "C:\\windows\\syswow64\\cmd.exe" /c "echo %PROCESSOR_ARCHITECTURE%" 2>/dev/null | tr -d '\r\n ')"
    if [ "$arch_info" = "x86" ]; then ok "32 位 WoW64 可用（实测 32 位进程报告 ARCH=x86）"
    else bad "32 位进程异常（报告 ARCH=${arch_info:-空}）"; fi
  else bad "前缀里没有 32 位运行库（syswow64 缺失）"; fi
  # 经典 D2 需要的 32 位图形/输入库
  miss=0
  for d in ddraw d3d8 d3d9 dinput dinput8 dsound opengl32 user32 gdi32; do
    [ -f "$DM_PREFIX/drive_c/windows/syswow64/$d.dll" ] || { bad "缺 32 位 $d.dll"; miss=1; }
  done
  [ "$miss" = 0 ] && ok "经典 D2 需要的 32 位图形/输入库齐全（ddraw/d3d8/d3d9/dinput/dsound）"
  if [ -d "$DM_PREFIX/drive_c/windows/Microsoft.NET" ] || [ -d "$DM_PREFIX/drive_c/windows/mono" ]; then
    note "检测到 .NET/Mono 痕迹（本游戏不需要）"
  fi
else
  bad "前缀不存在: $DM_PREFIX"
  note "运行 install-game.sh 之前需要先创建；或手动: WINEPREFIX=$DM_PREFIX wine64 wineboot"
fi

head_ "四、游戏"
if [ -f "$DM_GAME_DIR_HOST/Diablo II.exe" ]; then
  ok "游戏已安装: $DM_GAME_DIR_HOST/Diablo II.exe"
  for f in "Diablo II.exe" "Game.exe" "d2data.mpq" "d2exp.mpq" "fog.dll" "storm.dll"; do
    [ -f "$DM_GAME_DIR_HOST/$f" ] && ok "  $f" || note "  缺 $f"
  done
  if [ -f "$DM_GAME_DIR_HOST/glide3x.dll" ]; then
    ok "Glide 3D 包装器已就位（glide3x.dll）"
  else
    note "未安装 Glide 包装器：只能跑 2D 模式。想开 3D 请跑 $HERE/setup-glide.sh"
  fi
  mpq="$(ls -l "$DM_GAME_DIR_HOST"/*.mpq 2>/dev/null | wc -l | tr -d ' ')"
  ok "MPQ 数据文件: ${mpq} 个"
else
  bad "游戏尚未安装: $DM_GAME_DIR_HOST"
  note "运行 $HERE/install-game.sh"
fi

head_ "五、日志"
if [ -f "$DM_LOG" ]; then
  note "最近 12 行 ($DM_LOG):"
  tail -12 "$DM_LOG" | sed 's/^/      /'
else
  note "还没有日志（游戏还没启动过）"
fi

printf '\n'
