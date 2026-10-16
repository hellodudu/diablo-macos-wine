# 诊断工具

这些是为了**定位问题**而写的一次性小程序——每一个都对应排查过程中的一个具体疑问。
它们不参与日常运行，但如果你想在自己的机器上复核结论，可以编译运行。

| 源码 | 回答什么问题 | 相关条件 |
|---|---|---|
| `sigcheck.c` | Wine 能不能验证 Authenticode 签名？（用于否定「签名能力不足」这个猜测） | A |
| `vercheck.c` | 前缀**真正**对外声称的 Windows 版本是多少？（别信注册表 `CurrentVersion`） | A |
| `d3d12check.c` | 能不能建出 D3D12 设备、最高特性级别是几？（D4 硬要求 12_0） | B |
| `loadercheck.c` | D4 加载器硬查的 `kernel32.FindNextFileNameW` 在不在、能不能优雅失败？ | D |

## 编译

```bash
brew install mingw-w64

# 32 位（条件 A 的检查用；Battle.net 有 32 位组件）
i686-w64-mingw32-gcc   -O1 -o sigcheck32.exe  sigcheck.c   -lwintrust
i686-w64-mingw32-gcc   -O1 -o vercheck32.exe  vercheck.c

# 64 位（条件 B / D 的检查用；D4 是 64 位）
x86_64-w64-mingw32-gcc -O1 -o vercheck64.exe    vercheck.c
x86_64-w64-mingw32-gcc -O1 -o d3d12check64.exe  d3d12check.c -ld3d12 -ldxgi -ldxguid -luuid
x86_64-w64-mingw32-gcc -O1 -o loadercheck64.exe loadercheck.c
```

## 运行

⚠️ 三个必须注意的点：

1. **不要经 `arch -x86_64` 或 `nohup`** —— 它们是 Apple 签名的受限二进制，会把 `DYLD_*` 剥掉，
   导致 `freetype`/`gnutls` 加载失败。
2. `DYLD_FALLBACK_LIBRARY_PATH` 要指向引擎的 `lib`。
3. 要设 `WINE_SIMULATE_WRITECOPY=1`，否则 CEF 相关的进程会崩。

```bash
ENGINE=~/path/to/engine          # 含 bin/wine 与 lib/
PREFIX=~/path/to/prefix

WINEPREFIX="$PREFIX" \
DYLD_FALLBACK_LIBRARY_PATH="$ENGINE/lib:/usr/lib" \
ROSETTA_ADVERTISE_AVX=1 \
WINE_SIMULATE_WRITECOPY=1 \
WINEDEBUG=-all \
  "$ENGINE/bin/wine" 'Z:\path\to\d3d12check64.exe'
```

输出含义见 [`../docs/verification-2026-10-16.txt`](../docs/verification-2026-10-16.txt) 里记录的实例。

## 注意

这些是**诊断**工具，不是运行依赖。日常使用只需要 `scripts/` 里的脚本。
