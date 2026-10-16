/* vercheck.c — 权威地报告 Wine 前缀对外声称的 Windows 版本
 * 编译 32 位: i686-w64-mingw32-gcc   -O1 -o vercheck32.exe vercheck.c
 * 编译 64 位: x86_64-w64-mingw32-gcc -O1 -o vercheck64.exe vercheck.c
 */
#include <windows.h>
#include <stdio.h>

typedef LONG (WINAPI *PFN_RtlGetVersion)(PRTL_OSVERSIONINFOW);

int main(void)
{
    OSVERSIONINFOEXA os;
    RTL_OSVERSIONINFOW rtl;
    HMODULE nt;
    PFN_RtlGetVersion f;
    const char *w10 = "10.0";

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("指针宽度: %u 字节 (%s)\n", (unsigned)sizeof(void *),
           sizeof(void *) == 8 ? "64 位进程" : "32 位进程");

    ZeroMemory(&os, sizeof os);
    os.dwOSVersionInfoSize = sizeof os;
    if (GetVersionExA((OSVERSIONINFOA *)&os))
        printf("GetVersionEx:        %lu.%lu build %lu\n",
               (unsigned long)os.dwMajorVersion, (unsigned long)os.dwMinorVersion,
               (unsigned long)os.dwBuildNumber);
    else
        printf("GetVersionEx:        失败 (err=%lu)\n", GetLastError());

    nt = GetModuleHandleA("ntdll.dll");
    f = nt ? (PFN_RtlGetVersion)GetProcAddress(nt, "RtlGetVersion") : NULL;
    if (f) {
        ZeroMemory(&rtl, sizeof rtl);
        rtl.dwOSVersionInfoSize = sizeof rtl;
        if (f(&rtl) == 0)
            printf("RtlGetVersion:       %lu.%lu build %lu  <- 内核真正用的值\n",
                   (unsigned long)rtl.dwMajorVersion, (unsigned long)rtl.dwMinorVersion,
                   (unsigned long)rtl.dwBuildNumber);
    }

    {
        char buf[64] = {0};
        DWORD n = GetEnvironmentVariableA("PROCESSOR_ARCHITECTURE", buf, sizeof buf);
        printf("PROCESSOR_ARCH:      %s\n", n ? buf : "(未设置)");
    }

    /* 判定：Battle.net 要求 Win10+ */
    if (f) {
        ZeroMemory(&rtl, sizeof rtl); rtl.dwOSVersionInfoSize = sizeof rtl;
        if (f(&rtl) == 0) {
            int is10 = (rtl.dwMajorVersion > 6) ||
                       (rtl.dwMajorVersion == 6 && rtl.dwMinorVersion >= 4);
            printf("\n结论: %s（%s，Battle.net 要求 10.0+）\n",
                   is10 ? "满足 Battle.net 要求" : "不满足 Battle.net 要求",
                   rtl.dwMajorVersion > 6 ? "Win10+" : "Win8.1 或更早");
            return is10 ? 0 : 1;
        }
    }
    (void)w10;
    return 2;
}
