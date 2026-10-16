#!/bin/zsh
# ⚠️⚠️ 默认不要运行本脚本 ⚠️⚠️
#
# 2026-10-16 实测结论：**禁用 Overlay 会让战网客户端的更新失败**，
# 报错 3_Z3NTAGT00000839（AGT = Agent）。原因是 Agent 在更新时
# 需要校验/修复这些文件；文件被改名、被替换成 0 字节、或被设为
# 不可变（chflags uchg）时，Agent 修不了就报错。
#
# 而"卡在正在登录《暗黑破坏神IV》"这个问题，用【直启 D4】就能绕开：
#     Diablo IV.exe -nostreamline -sso -launch -uid fenris   （见 run-d4.sh）
# 直启时客户端不会注入 Overlay，所以**没必要禁用 Overlay**。
#
# 只有在一种情况下才需要本脚本：你坚持用客户端界面上的「开始游戏」按钮，
# 且确实卡在「正在登录」。那时：
#     ./disable-overlay.sh --force          # 临时禁用（会导致更新失败）
#     ./disable-overlay.sh --restore        # 更新前务必还原
# 禁用 Battle.net 的 Overlay 组件 —— 国服 D4 能否进游戏的关键一步
#
# 为什么必须做：
#   2026 年 5 月的一次更新后，战网 Overlay 在 Wine 环境下注入 D4 时会卡住
#   登录后的初始化流程，症状是**永久卡在「正在登录《暗黑破坏神IV》」，且无法正常关闭**。
#
# ⚠️ 两个踩过的坑：
#   1. Overlay 有【两份】副本。客户端启动游戏时用的是 ProgramData 那份：
#        [GameLaunchController] Using agent overlay binary: C:/ProgramData/Battle.net/bdk\battlenet.overlay.runtime.exe
#      只禁用 Program Files 那份，D4 照样卡住。
#   2. 【单纯改名会被客户端修复】。客户端在启动游戏前会校验这些文件并重新下载/恢复，
#      所以"启动前重命名"永远在赛跑。必须让文件无法被覆盖：
#      改成 0 字节占位文件 + chflags uchg（用户不可变，连删除都会被拒绝）。
#
# 还原方式：./disable-overlay.sh --restore
set -u

HERE="${0:A:h}"
source "$HERE/env.sh" 2>/dev/null

VERBOSE=0
RESTORE=0
FORCE=0
for a in "$@"; do
  case "$a" in
    --verbose) VERBOSE=1 ;;
    --restore) RESTORE=1 ;;
    --force)   FORCE=1 ;;
  esac
done

if [ "$RESTORE" = 0 ] && [ "$FORCE" = 0 ]; then
  print -r -- "本脚本默认不执行：禁用 Overlay 会让战网客户端的更新失败"
  print -r -- "（报错 3_Z3NTAGT00000839），而用 run-d4.sh 直启 D4 本来就不需要禁用它。"
  print -r -- ""
  print -r -- "确实需要（坚持用客户端「开始游戏」且卡在正在登录）才加 --force："
  print -r -- "  ./disable-overlay.sh --force     # 禁用"
  print -r -- "  ./disable-overlay.sh --restore   # 更新前还原"
  exit 0
fi

targets() {
  find "$WINEPREFIX/drive_c" \( -iname "battlenet.overlay*" -o -iname "*overlay*.dll" -o -iname "*overlay*.exe" \) 2>/dev/null
}

if [ "$RESTORE" = 1 ]; then
  n=0
  for f in $(targets); do
    case "$f" in
      *.disabled) chflags nouchg "$f" 2>/dev/null; mv -f "$f" "${f%.disabled}" 2>/dev/null && n=$((n+1)) ;;
    esac
  done
  # 清掉占位文件
  for f in $(targets); do
    [ -f "$f" ] && [ ! -s "$f" ] && [ "$(basename "$f")" != "*.disabled" ] && {
      chflags nouchg "$f" 2>/dev/null; rm -f "$f" 2>/dev/null && n=$((n+1))
    }
  done
  print -r -- "已还原 $n 项（下次启动战网时会重新下载 Overlay）"
  exit 0
fi

changed=0
for f in $(targets); do
  case "$f" in *.disabled) continue ;; esac
  [ -f "$f" ] || continue

  # 1) 备份原文件（改名保留）
  chflags nouchg "$f" 2>/dev/null
  if [ -s "$f" ]; then
    mv -f "$f" "$f.disabled" 2>/dev/null || continue
  else
    continue   # 已经是占位文件
  fi
  # 2) 在原位置放 0 字节占位并设为不可变，防止客户端校验后重新下载
  : > "$f" 2>/dev/null || { mv -f "$f.disabled" "$f" 2>/dev/null; continue; }
  chflags uchg "$f" 2>/dev/null

  changed=$((changed+1))
  [ "$VERBOSE" = 1 ] && printf '  已禁用: %s（0字节占位 + 不可变）\n' "$(echo "$f" | sed "s|$WINEPREFIX/drive_c|C:|")"
done

# 兜底：确保已有的 .disabled 备份也不会被误用
for f in $(targets); do
  case "$f" in *.disabled) chflags uchg "$f" 2>/dev/null ;; esac
done

if [ "$VERBOSE" = 1 ]; then
  if [ "$changed" -gt 0 ]; then
    print -r -- "  本次处理 $changed 个 Overlay 文件"
  else
    print -r -- "  Overlay 已处于禁用状态"
  fi
fi
exit 0
