/* sigcheck.c — 精确判定 Wine 能否验证 Authenticode 数字签名
 *
 * 背景：Battle.net 的 Agent 日志显示
 *   "Unable to validate connecting process (32)"
 *   "Failed Caller authorization due to signature for 'Battle.net-Setup-enUS.exe'(32)"
 *   -> Agent init returned status code=401
 * 也就是它要校验连接进程的 Authenticode 签名，而这一步失败了。
 * 这个程序直接调用同一个 API（WinVerifyTrust），把 Wine 的真实返回值打出来。
 *
 * 编译：
 *   i686-w64-mingw32-gcc   -O1 -o sigcheck32.exe sigcheck.c -lwintrust
 *   x86_64-w64-mingw32-gcc -O1 -o sigcheck64.exe sigcheck.c -lwintrust
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wintrust.h>
#include <softpub.h>
#include <stdio.h>

static const char *describe(LONG r)
{
    switch ((unsigned long)r) {
    case 0x00000000UL: return "ERROR_SUCCESS —— 签名有效且受信任";
    case 0x800B0100UL: return "TRUST_E_NOSIGNATURE —— 找不到签名（Wine 常见）";
    case 0x800B0101UL: return "CERT_E_EXPIRED —— 证书已过期";
    case 0x800B0109UL: return "CERT_E_UNTRUSTEDROOT —— 根证书不受信任";
    case 0x800B010AUL: return "CERT_E_CHAINING —— 证书链无法构建";
    case 0x800B010CUL: return "CERT_E_REVOKED";
    case 0x800B0110UL: return "TRUST_E_CERT_SIGNATURE";
    case 0x80096010UL: return "TRUST_E_BAD_DIGEST —— 摘要不匹配";
    case 0x800B0001UL: return "TRUST_E_PROVIDER_UNKNOWN —— 没有签名验证提供程序";
    case 0x800B0003UL: return "TRUST_E_SUBJECT_FORM_UNKNOWN";
    case 0x800B0004UL: return "TRUST_E_SUBJECT_NOT_TRUSTED —— 主体不受信任";
    case 0x80092003UL: return "CRYPT_E_FILE_ERROR";
    case 0x80070057UL: return "E_INVALIDARG";
    case 0x80004001UL: return "E_NOTIMPL —— 未实现";
    case 0x80004005UL: return "E_FAIL";
    default:           return "(未知返回值)";
    }
}

int main(int argc, char **argv)
{
    WCHAR wpath[MAX_PATH * 2];
    WINTRUST_FILE_INFO fi;
    WINTRUST_DATA wd;
    GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    LONG r;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) { printf("用法: sigcheck.exe <某个 exe 的 Windows 路径>\n"); return 2; }

    printf("指针宽度: %u 字节 (%s)\n", (unsigned)sizeof(void *),
           sizeof(void *) == 8 ? "64 位" : "32 位");
    printf("待检文件: %s\n", argv[1]);

    MultiByteToWideChar(CP_ACP, 0, argv[1], -1, wpath, sizeof wpath / sizeof wpath[0]);

    if (GetFileAttributesW(wpath) == INVALID_FILE_ATTRIBUTES) {
        printf("!! 文件不存在或不可访问 (err=%lu)\n", GetLastError());
        return 3;
    }

    /* 先看文件里到底有没有嵌入签名 */
    {
        HMODULE wt = LoadLibraryA("wintrust.dll");
        printf("wintrust.dll: %s\n", wt ? "可加载" : "无法加载");
        if (wt) FreeLibrary(wt);
    }

    ZeroMemory(&fi, sizeof fi);
    fi.cbStruct = sizeof fi;
    fi.pcwszFilePath = wpath;

    ZeroMemory(&wd, sizeof wd);
    wd.cbStruct = sizeof wd;
    wd.dwUIChoice = WTD_UI_NONE;
    wd.fdwRevocationChecks = WTD_REVOKE_NONE;
    wd.dwUnionChoice = WTD_CHOICE_FILE;
    wd.pFile = &fi;
    wd.dwStateAction = WTD_STATEACTION_VERIFY;

    r = WinVerifyTrust(NULL, &action, &wd);
    printf("\nWinVerifyTrust -> 0x%08lX\n   %s\n", (unsigned long)r, describe(r));

    wd.dwStateAction = WTD_STATEACTION_CLOSE;
    WinVerifyTrust(NULL, &action, &wd);

    printf("\n判定: %s\n", r == 0
        ? "Wine 能验证该签名的真实性 —— Agent 的签名校验有可能通过"
        : "Wine 无法确证该签名 —— Agent 的 caller authorization 会失败并返回 401");
    return r == 0 ? 0 : 1;
}
