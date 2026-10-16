#!/bin/zsh
# Diablo IV 国服 环境自检：只读，不改动任何东西
set -u

HERE="${0:A:h}"
source "$HERE/env.sh" 2>/dev/null

ok()   { printf '  \033[32m✅\033[0m %s\n' "$*" }
bad()  { printf '  \033[31m❌\033[0m %s\n' "$*" }
note() { printf '  \033[33m·\033[0m %s\n' "$*" }
sec()  { printf '\n\033[1m%s\033[0m\n' "$*" }

printf 'Diablo IV 国服 on Apple Silicon —— 环境自检\n'
printf '区域: %s\n' "$DM_REGION_LABEL"

sec "一、引擎（必须同时满足 Agent 授权与 DX12，缺一不可）"
if [ -x "$WINE" ]; then
  ok "Wine: $($WINE --version 2>/dev/null | head -1)"
  note "路径: $WINE"
else
  bad "找不到 Wine: $WINE"
fi

# 条件 A：Agent 授权靠 CodeWeavers 血统（不是旧式/新式 WoW64 本身，而是它的进程路径解析）
if [ -f "$ENGINE/lib/wine/x86_64-windows/d3d12.dll" ] && grep -qa "D3DMetalDLLsBase" "$ENGINE/lib/wine/x86_64-windows/d3d12.dll" 2>/dev/null; then
  ok "D3DMetal PE 垫片已接入（条件 B：DX12）"
else
  bad "缺 Apple 的 D3DMetal 垫片 —— DX12 只有 FL 11_0，D4 跑不起来"
fi
for f in d3d11 d3d12 dxgi; do
  [ -L "$ENGINE/lib/wine/x86_64-unix/$f.so" ] || { bad "$f.so 不是 symlink（复制会破坏 @loader_path 解析）"; break; }
done
[ -f "$ENGINE/lib/external/libd3dshared.dylib" ] && ok "lib/external/libd3dshared.dylib 就位" || bad "缺 libd3dshared.dylib"

# 致命陷阱：经 arch/nohup 启动会剥掉 DYLD_*，字体全无
if [ -n "${DYLD_FALLBACK_LIBRARY_PATH:-}" ]; then
  ok "DYLD_FALLBACK_LIBRARY_PATH 已设置（freetype/gnutls 能找到）"
else
  bad "DYLD_FALLBACK_LIBRARY_PATH 未设置 —— 字体与 gnutls 会加载失败"
fi
note "启动时必须【直接】执行 \$WINE；经 arch -x86_64 或 nohup 会剥掉 DYLD_*（Soju README 有说明）"

sec "二、DX12 能力（D4 硬要求 FL 12_0）"
D3D12C="$HERE/tools/d3d12check64.exe"
if [ -x "$WINE" ] && [ -f "$D3D12C" ]; then
  r=$("$WINE" "Z:${D3D12C//\//\\}" 2>/dev/null | tr -d '\r')
  if printf '%s' "$r" | grep -q "D3D12CreateDevice(12_0) 成功"; then
    lvl=$(printf '%s' "$r" | grep -o "最高支持特性级别: [0-9_]*" | head -1)
    ok "D3D12CreateDevice(12_0) 成功 —— $lvl"
  else
    bad "DX12 12_0 不可用：$(printf '%s' "$r" | grep -a '^\[FAIL\]' | head -1)"
  fi
else
  note "缺 tools/d3d12check64.exe，无法实测"
fi

sec "三、前缀"
if [ -d "$WINEPREFIX" ]; then
  ok "前缀: $WINEPREFIX（$(du -sh "$WINEPREFIX" 2>/dev/null | cut -f1)）"
  VC="$HERE/tools/vercheck64.exe"
  if [ -f "$VC" ]; then
    rv=$("$WINE" "Z:${VC//\//\\}" 2>/dev/null | tr -d '\r' | grep -a "RtlGetVersion" | head -1)
    printf '%s' "$rv" | grep -q "10\." && ok "${rv##*:}（权威值）" || note "系统版本: ${rv:-读不到}"
  fi
else
  bad "前缀不存在: $WINEPREFIX"
fi

sec "四、安装进度"
if [ -f "$BNET_DIR_HOST/Battle.net Launcher.exe" ]; then
  ok "Battle.net 已安装（$(du -sh "$BNET_DIR_HOST" 2>/dev/null | cut -f1)）"
  fails=$(cat $AGENT_LOG_DIR/Agent.*/Logs/Agent-*.log(N) 2>/dev/null | grep -ac "Failed Caller authorization")
  if [ "${fails:-0}" = "0" ]; then
    ok "Agent caller authorization 失败次数: 0（条件 A 满足）"
  else
    bad "Agent caller authorization 失败 ${fails} 次 —— 引擎不对"
  fi
  # 区域判定：看客户端日志里的 region=
  REG=$(grep -ah "Login parameters changed" $WINEPREFIX/drive_c/users/*/AppData/Local/Battle.net/Logs/battle.net-*.log(N) 2>/dev/null | tail -1 | grep -o "region=[A-Z]*")
  [ -n "$REG" ] && ok "客户端当前连接: $REG" || note "客户端尚未启动过（region 未知）"
else
  bad "Battle.net 未安装 → 跑 install-battlenet.sh"
fi
if [ -f "$D4_DIR_HOST/Diablo IV Launcher.exe" ]; then
  ok "Diablo IV 已安装（$(du -sh "$D4_DIR_HOST" 2>/dev/null | cut -f1)）"
else
  note "Diablo IV 未安装 → 打开 Battle.net 登录后在客户端里安装"
fi

sec "五、关键环境变量（三条缺一不可）"
for v in WINE_SIMULATE_WRITECOPY ROSETTA_ADVERTISE_AVX D3DM_SUPPORT_DXR; do
  eval "val=\${$v:-}"
  [ -n "$val" ] && ok "$v=$val" || bad "$v 未设置"
done
note "WINE_SIMULATE_WRITECOPY 缺失 → CEF 渲染器 int3 崩溃 → 登录界面黑屏"

sec "六、登录界面（条件 C：两部分，缺一黑屏）"
# C-1 CEF 渲染进程不能崩（需要 WINE_SIMULATE_WRITECOPY=1）
CL=$(ls -t $WINEPREFIX/drive_c/users/*/AppData/Local/Battle.net/Logs/battle.net-*.log(N) 2>/dev/null | head -1)
if [ -n "$CL" ]; then
  cr=$(grep -ac "Render process was terminated" "$CL" 2>/dev/null)
  ld=$(grep -ah "UAuth: finished loading" "$CL" 2>/dev/null | tail -1 | grep -o "statusCode=[0-9]*")
  [ "${cr:-0}" = "0" ] && ok "CEF 渲染进程未被终止" || bad "CEF 渲染进程被终止 ${cr} 次 —— 检查 WINE_SIMULATE_WRITECOPY"
  [ -n "$ld" ] && { [ "$ld" = "statusCode=200" ] && ok "登录页加载成功（$ld）" || note "登录页返回 $ld"; } || note "尚未记录到登录页加载事件"
fi
# C-2 必须以 $BNET_ARGS 直接启动 Battle.net.exe，否则 CEF 另起 GPU 进程并崩 → 画面全黑
PSF=$(mktemp)
ps -eo command > "$PSF"
if grep -q -- "Battle.net.exe" "$PSF" 2>/dev/null && grep -- "Battle.net.exe" "$PSF" | grep -q -- "in-process-gpu"; then
  g=$(grep -- "Battle.net.exe --type=gpu-process" "$PSF" | wc -l | tr -d ' ')
  [ "$g" = "0" ] && ok "以 --in-process-gpu 启动，GPU 进程 0（CEF 能合成画面）" \
                 || note "仍有 $g 个 GPU 进程（可能未完全生效）"
  grep -q -- "use-gl=swiftshader" "$PSF" && ok "--use-gl=swiftshader 已传入（软件 GL）" || bad "缺 --use-gl=swiftshader"
else
  note "客户端当前未运行（或未经 \$BNET_ARGS 启动）—— 用 run-battlenet.sh 启动"
fi
rm -f "$PSF"
for f in "$D4_LOG_DIR"/battlenet*.log(N); do
  n=$(grep -ac "0x80000003\|virtual_setup_exception" "$f" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] && note "$(basename "$f"): CEF int3 异常 $n 次"
done

sec "七、D4 启动前提（条件 D）"
# D4 的加载器会硬性查询 kernel32.FindNextFileNameW；Wine 曾缺此导出导致完全无法启动
LC="$HERE/tools/loadercheck64.exe"
if [ -x "$WINE" ] && [ -f "$LC" ]; then
  out=$("$WINE" "Z:${LC//\//\\}" 2>/dev/null | tr -d '\r')
  if printf '%s' "$out" | grep -q "kernel32.FindNextFileNameW 存在"; then
    ok "kernel32.FindNextFileNameW 存在且可运行时解析（D4 加载器的硬性检查）"
  else
    bad "缺 kernel32.FindNextFileNameW —— D4 会卡在启动（社区已知问题）"
  fi
  printf '%s' "$out" | grep -q "ntdll.NtQuerySystemInformation 存在" && ok "ntdll.NtQuerySystemInformation 存在"
else
  note "缺 tools/loadercheck64.exe，无法实测"
fi
# Overlay 必须在禁用状态，否则 D4 会卡在「正在登录《暗黑破坏神IV》」
if [ -f "$BNET_DIR_HOST/Battle.net Launcher.exe" ]; then
  ov=$(find "$BNET_DIR_HOST" -iname "*overlay*" -not -name "*.disabled" 2>/dev/null | wc -l | tr -d ' ')
  [ "$ov" = "0" ] && ok "Battle.net Overlay 已禁用（否则 D4 会卡在「正在登录」）" \
                  || bad "还有 $ov 个 Overlay 文件未禁用 → 跑 disable-overlay.sh"
fi

sec "八、磁盘"
df -h / | tail -1 | awk '{print "  可用: "$4"   已用: "$3}'
note "Diablo IV 完整安装约 90 GB 以上"

sec "九、日志"
[ -d "$D4_LOG_DIR" ] && for f in "$D4_LOG_DIR"/*.log(N); do note "$(basename "$f")  （$(wc -l < "$f" | tr -d ' ') 行）"; done

printf '\n'
