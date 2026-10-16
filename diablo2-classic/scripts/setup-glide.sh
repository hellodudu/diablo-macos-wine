#!/bin/bash
# 把 Sven's Glide Wrapper 装进游戏目录，开启 3D 透视模式。
# 包装器是免费软件，已下载在 staging/ 下（glide3x.dll + glide-init.exe）。
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/config.env"

GAME="$DM_GAME_DIR_HOST"
STAGE="$HERE/staging"

[ -d "$GAME" ] || { echo "游戏目录不存在: $GAME"; echo "请先安装游戏（install-game.sh）"; exit 1; }
[ -f "$STAGE/glide3x.dll" ] || { echo "找不到 $STAGE/glide3x.dll"; exit 1; }

cp -v "$STAGE/glide3x.dll"   "$GAME/"
cp -v "$STAGE/glide-init.exe" "$GAME/"
cp -v "$STAGE/glide-readme.txt" "$GAME/" 2>/dev/null || true

cat <<EOF

已安装 Glide 包装器到：
  $GAME

接下来：
  1. 双击 Diablo II.app 前，先把 config.env 里的 DM_GLIDE 改成 1
     （或者直接跑：./run-game.sh -3dfx）
  2. 想调 3D 分辨率/刷新率等设置，在游戏目录里运行 glide-init.exe：
     WINEPREFIX="$DM_PREFIX" "$DM_WINE_BIN" "C:\\Program Files (x86)\\Diablo II\\glide-init.exe"
  3. 包装器提供的是 OpenGL 渲染的 3D 透视模式；如果画面异常，
     把 DM_GLIDE 改回 0 用 2D 模式即可（2D 模式最稳）。
EOF
