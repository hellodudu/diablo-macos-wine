/* loadercheck.c — 验证 D4 加载器依赖的 kernel32 函数在本引擎上真正可用
 *
 * 背景：2026 年 5 月 D4 更新后，diablo_iv_loader.dll 会硬性查询
 * KERNEL32.dll 的 FindNextFileNameW；Wine 当时没有这个导出，导致
 * Linux/Wine 用户完全无法启动游戏（暴雪论坛有 600+ 楼的长贴）。
 * 上游后来加了 stub，Proton 也修了。这里验证我们的引擎是否具备。
 *
 * 注意：PE 里"存在导出"不等于"运行时可解析"——可能是转发到另一个
 * 模块（如 kernelbase），而那个模块未必有实现。所以这里用
 * GetProcAddress 实际解析，并把函数真正调用一次看是否优雅失败。
 *
 * 编译（D4 是 64 位）：
 *   x86_64-w64-mingw32-gcc -O1 -o loadercheck64.exe loadercheck.c
 *   i686-w64-mingw32-gcc   -O1 -o loadercheck32.exe loadercheck.c
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static int fails = 0;

static void ok(const char *m)   { printf("[ OK ]  %s\n", m); fflush(stdout); }
static void bad(const char *m)  { printf("[FAIL]  %s\n", m); fflush(stdout); fails++; }
static void note(const char *m) { printf("[ .. ]  %s\n", m); fflush(stdout); }

/* 真正把 FindNextFileNameW 调一次，确认不会崩、只是优雅失败 */
static void call_findnext(void)
{
    typedef BOOL (WINAPI *PFN)(HANDLE, LPDWORD, LPWSTR);
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    PFN f = k32 ? (PFN)GetProcAddress(k32, "FindNextFileNameW") : NULL;
    DWORD len = MAX_PATH;
    WCHAR buf[MAX_PATH];
    BOOL r;

    if (!f) { bad("FindNextFileNameW 运行时可解析（GetProcAddress 返回 NULL）"); return; }
    ok("FindNextFileNameW 运行时可解析");

    /* 用一个明显无效的句柄调用：期望返回 FALSE 并设置错误码，而不是崩溃 */
    SetLastError(0);
    r = f(INVALID_HANDLE_VALUE, &len, buf);
    if (!r) {
        char m[160];
        snprintf(m, sizeof m, "用无效句柄调用返回 FALSE（err=%lu）—— 行为正确，非崩溃", GetLastError());
        ok(m);
    } else {
        note("用无效句柄调用竟返回 TRUE（异常但不致命）");
    }
}

int main(void)
{
    HINSTANCE h;
    const char *names[] = {
        "FindFirstFileNameW", "FindNextFileNameW",
        "FindFirstFileNameTransactedW", "FindNextFileNameTransactedW",
        "VirtualProtect", "CreateFileMappingW", "NtQuerySystemInformation",
    };
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== D4 加载器依赖项检测 ===\n");
    printf("进程位宽: %u 字节 (%s)\n", (unsigned)sizeof(void *),
           sizeof(void *) == 8 ? "64 位" : "32 位");

    /* 报一下 Windows 版本，便于比对社区报告 */
    {
        OSVERSIONINFOEXA os;
        ZeroMemory(&os, sizeof os); os.dwOSVersionInfoSize = sizeof os;
        if (GetVersionExA((OSVERSIONINFOA *)&os))
            printf("报告的系统: %lu.%lu build %lu\n",
                   (unsigned long)os.dwMajorVersion, (unsigned long)os.dwMinorVersion,
                   (unsigned long)os.dwBuildNumber);
    }

    printf("\n-- kernel32 关键导出 --\n");
    h = GetModuleHandleA("kernel32.dll");
    if (!h) { bad("kernel32.dll 未加载"); return 1; }
    ok("kernel32.dll 已加载");

    for (i = 0; i < (int)(sizeof names / sizeof names[0]); i++) {
        /* NtQuerySystemInformation 属于 ntdll，不在 kernel32 —— 单独处理 */
        if (strcmp(names[i], "NtQuerySystemInformation") == 0) {
            HMODULE nt = GetModuleHandleA("ntdll.dll");
            if (nt && GetProcAddress(nt, names[i])) ok("ntdll.NtQuerySystemInformation 存在");
            else bad("ntdll.NtQuerySystemInformation 缺失");
            continue;
        }
        if (GetProcAddress(h, names[i])) {
            char m[128]; snprintf(m, sizeof m, "kernel32.%s 存在", names[i]); ok(m);
        } else if (strstr(names[i], "Transacted")) {
            char m[128]; snprintf(m, sizeof m, "kernel32.%s 不存在（D4 不依赖，仅记录）", names[i]); note(m);
        } else {
            char m[128]; snprintf(m, sizeof m, "kernel32.%s 缺失", names[i]); bad(m);
        }
    }

    printf("\n-- 关键函数实际调用 --\n");
    call_findnext();

    printf("\n=== 结论 ===\n");
    if (fails == 0) printf("通过 —— D4 加载器在这台机器的引擎上具备启动前提\n");
    else            printf("%d 项失败 —— D4 加载器可能在启动时被卡住\n", fails);
    return fails == 0 ? 0 : 1;
}
