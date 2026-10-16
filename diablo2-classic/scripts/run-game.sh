#!/bin/bash
# 启动 Diablo II。可由 Diablo II.app 双击调用，也可直接在终端运行。
# 用法：
#   ./run-game.sh              正常启动
#   ./run-game.sh -3dfx        这次用 Glide 3D 模式启动
#   ./run-game.sh <任意参数>   参数会原样传给游戏
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.env"

msg()   { printf '%s\n' "$*"; }
alert() {  # 从 Finder 双击时没有终端，用系统弹窗告知
  msg "$*"
  [ -n "${DM_NO_DIALOG:-}" ] && return
  [ -t 1 ] && return
  /usr/bin/osascript -e "display dialog \"$*\"" \
    -e 'buttons {"好"} default button 1 with title "Diablo II"' >/dev/null 2>&1
}

[ -x "$DM_WINE_BIN" ] || { alert "找不到 Wine 引擎：
$DM_WINE_BIN
请修改 $HERE/config.env 里的 DM_WINE_BIN"; exit 1; }

if [ ! -f "$DM_GAME_DIR_HOST/Diablo II.exe" ]; then
  alert "还没有安装游戏。

先运行 $HERE/install-game.sh 来执行 Blizzard 官方安装器，
安装完成后再双击本程序。"
  exit 1
fi

export WINEPREFIX="$DM_PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree,mshtml="
[ -n "$DM_AUDIO_DRIVER" ] && export AUDIODRIVER="$DM_AUDIO_DRIVER"

# 参数：DM_GLIDE=1 或命令行给 -3dfx 时用 Glide 3D
args="$DM_ARGS"
if [ "${1:-}" = "-3dfx" ]; then
  args="$DM_GLIDE_ARGS"; shift
elif [ "$DM_GLIDE" = "1" ]; then
  args="$DM_ARGS $DM_GLIDE_ARGS"
fi

# 虚拟桌面：老游戏全屏切换分辨率时在 macOS 上容易出问题，
# 设了 DM_VIRTUAL_DESKTOP=800x600 就走 Wine 的虚拟桌面，最稳。
launch_cmd=("$DM_WINE_BIN")
launch_desc="$DM_GAME_EXE_WIN"
if [ -n "${DM_VIRTUAL_DESKTOP:-}" ]; then
  launch_cmd+=("explorer" "/desktop=DiabloII,$DM_VIRTUAL_DESKTOP")
  launch_desc="explorer /desktop=DiabloII,$DM_VIRTUAL_DESKTOP  $DM_GAME_EXE_WIN"
fi
launch_cmd+=("$DM_GAME_EXE_WIN")
# shellcheck disable=SC2086
[ -n "$args" ] && launch_cmd+=($args)
[ "$#" -gt 0 ] && launch_cmd+=("$@")

msg "引擎:   $DM_WINE_BIN"
msg "前缀:   $WINEPREFIX"
msg "启动:   $launch_desc $args $*"
msg "日志:   $DM_LOG"

{
  echo "===== $(date '+%F %T') ====="
  echo "cmd: $launch_desc $args $*"
} >> "$DM_LOG"

# exec 让游戏接替进程；关掉游戏窗口即结束
exec "${launch_cmd[@]}" >> "$DM_LOG" 2>&1
