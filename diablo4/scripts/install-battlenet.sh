#!/bin/zsh
# 运行官方 Battle.net 安装器，为安装《暗黑破坏神 IV》做准备。
# 区域由 DM_REGION 决定（cn = 国服 / intl = 国际服），安装器路径取自 env.sh 的 BNET_INSTALLER。
# 用法:
#   ./install-battlenet.sh              # 用 env.sh 里当前区域的安装器
#   DM_REGION=intl ./install-battlenet.sh
#   ./install-battlenet.sh /path/to/别的安装器.exe
set -u

HERE="${0:A:h}"
source "$HERE/env.sh"

INST="${1:-$BNET_INSTALLER}"
[ -f "$INST" ] || { print -r -- "找不到安装器: $INST"; exit 1; }

# 前缀不存在就先初始化（Wine 11.9 的新式 WoW64）
if [ ! -d "$WINEPREFIX" ]; then
  print -r -- "初始化前缀: $WINEPREFIX"
  mkdir -p "$WINEPREFIX"
  "$WINE" wineboot --init 2>&1 | grep -avE "fixme|wine: created|wine: configuration" | head -5
fi

print -r -- ""
print -r -- "区域:   $DM_REGION_LABEL"
print -r -- "引擎:   $($WINE --version 2>/dev/null | head -1)"
print -r -- "前缀:   $WINEPREFIX"
print -r -- "安装器: $INST"
print -r -- ""
print -r -- "安装界面出现后一路默认即可；装完 Battle.net 会自己启动并要求登录。"
print -r -- "登录凭据由你自己输入。"
print -r -- ""

"$WINE" "Z:${INST//\//\\}" 2>&1 | tee -a "$D4_LOG_DIR/battlenet-install-$DM_REGION.log"
