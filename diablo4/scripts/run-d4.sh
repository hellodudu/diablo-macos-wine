#!/bin/zsh
# 启动《暗黑破坏神 IV》
#
# ============ 实测结论：这样启动才对 ============
#  D4 用 -sso 单点登录，令牌由**战网客户端**通过本地 IPC 提供。
#  所以：客户端必须先运行并已登录，然后用客户端启动游戏时的【原始命令行】直接拉起游戏：
#
#      Diablo IV.exe -nostreamline -sso -launch -uid fenris
#
#  两条走过的弯路，都不要再走：
#   1. 直接跑 Diablo IV Launcher.exe → 没有 SSO 令牌，MoltenVK 初始化后就没了下文。
#   2. 用 Battle.net.exe --exec="launch fenris" → 实测只触发更新检查，不会启动游戏。
#
#  另一个好处：这样【直接】启动 D4，客户端就没机会把 Overlay 注入进来，
#  顺带绕开了「卡在正在登录《暗黑破坏神IV》」那个已知问题。
set -u

HERE="${0:A:h}"
source "$HERE/env.sh"

# 仍重打一次 Overlay 禁用（走客户端 Play 按钮时有用）

if [ ! -f "$D4_DIR_HOST/Diablo IV.exe" ]; then
  print -r -- "尚未安装 Diablo IV（$D4_DIR_HOST）"
  print -r -- "请先运行: $HERE/run-battlenet.sh  然后在客户端里安装"
  exit 1
fi

# 客户端没在跑就拿不到 SSO 令牌
if ! ps ax -o command | grep -q 'Battle.net.exe'; then
  print -r -- "战网客户端未运行 —— 它负责给 D4 提供 SSO 登录令牌。"
  print -r -- ""
  print -r -- "请先执行:  $HERE/run-battlenet.sh"
  print -r -- "等它登录完成（日志里出现 Logged into Battle.net successfully）后，"
  print -r -- "再运行一次本脚本即可。"
  exit 1
fi

print -r -- "区域: $DM_REGION_LABEL"
print -r -- "引擎: $($WINE --version 2>/dev/null | head -1)"
print -r -- "芯片: $DM_ARCH（图形后端 $DM_GRAPHICS_BACKEND）"
print -r -- "启动: Diablo IV.exe -nostreamline -sso -launch -uid fenris"
print -r -- "说明: 客户端保持运行；不要关掉它，否则 SSO 令牌失效。"
print -r -- ""

# Intel 上明确给出结论，避免白等
if [ "$DM_APPLE_SILICON" != "1" ]; then
  print -r -- "⚠️  当前是 Intel（x86_64）Mac：D4 预期【无法运行】。"
  print -r -- "    原因：D4 需要 DX12 feature level 12_0，该能力来自 Apple 的 D3DMetal，"
  print -r -- "    而 Apple 官方 GPTK 的前置条件明确要求 Apple 芯片。"
  print -r -- "    脚本在 Intel 上仍会正常启动，但游戏会在 DX12 初始化阶段失败。"
  print -r -- "    详见 docs/FINDINGS.md 第八节。"
  print -r -- ""
fi

{
  print -r -- "===== $(date '+%F %T') ====="
  print -r -- "direct launch: Diablo IV.exe -nostreamline -sso -launch -uid fenris"
} >> "$D4_LOG_DIR/d4.log"

exec "$WINE" "$D4_EXE_WIN" -nostreamline -sso -launch -uid fenris
