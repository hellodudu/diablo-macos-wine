#!/bin/bash
# 运行 Blizzard 官方的经典版《暗黑破坏神 II》安装器。
#
# 你需要先从暴雪官网下载安装器（需要你的账号已绑定该游戏）：
#   https://us.support.blizzard.com/en/help/article/13867
# 下载后放到 ~/Downloads 或本目录的 staging/ 下，再运行本脚本；脚本会自动找到它。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.env"

if [ ! -x "$DM_WINE_BIN" ]; then
  echo "找不到 Wine 引擎：$DM_WINE_BIN"; echo "请修改 $HERE/config.env 里的 DM_WINE_BIN"; exit 1
fi

# 找安装器：本体和资料片的官方文件名形如 Downloader_Diablo2_*.exe
IFS=$'\n'
found=()
for pat in "Downloader_Diablo*.exe" "Diablo*Installer*.exe" "Diablo*Setup*.exe" "Setup_Diablo*.exe"; do
  for d in "$HOME/Downloads" "$HERE/staging" "$HERE"; do
    for f in "$d"/$pat; do [ -f "$f" ] && found+=("$f"); done
  done
done
unset IFS

if [ "${#found[@]}" -eq 0 ]; then
  cat <<'EOF'
没有找到 Blizzard 安装器。

请先到下面这个页面下载（需要你的战网账号已绑定该游戏）：
  https://us.support.blizzard.com/en/help/article/13867

《暗黑破坏神 II》本体和《毁灭之王》资料片各有一个安装器，两个都要下。
下载完放到 ~/Downloads，然后重新运行本脚本即可。

提示：本仓库不提供、也不协助获取游戏文件本身。
EOF
  exit 1
fi

echo "找到以下安装器："
for i in "${!found[@]}"; do printf '  [%d] %s\n' "$i" "${found[$i]}"; done
echo
printf '要运行哪一个？（直接回车 = 0，q = 退出）> '
read -r pick </dev/tty
case "$pick" in q|Q) exit 0;; "") pick=0;; esac
inst="${found[$pick]:-}"
[ -n "$inst" ] || { echo "选择无效"; exit 1; }

export WINEPREFIX="$DM_PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="mscoree,mshtml="

echo
echo "正在用 Wine 运行：$inst"
echo "安装路径保持默认（C:\\Program Files (x86)\\Diablo II）即可。"
echo "安装器会要求输入 16 位 CD key。"
echo

# 安装器是 Windows 程序，路径需要转成 Z:\ 形式
winpath="Z:$(printf '%s' "$inst" | tr '/' '\\')"
exec "$DM_WINE_BIN" "$winpath"
