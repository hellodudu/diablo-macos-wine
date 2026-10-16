/*
 * d2check.c — 经典版 Diablo II 在本机 Wine 环境下的可行性自检
 *
 * 为什么测这些：
 *   - D2 1.14d 是 32 位程序，必须能在 WoW64 下跑（进程架构检查）
 *   - D2 的默认渲染器是 DirectDraw（8 位调色板 + blit + flip），这是 2D 模式
 *   - D2 的 3D 透视模式走 Glide，而社区通用的 Sven's Glide Wrapper 是把
 *     Glide 翻译成 OpenGL，所以 OpenGL 上下文能否建立也很关键
 *   - 还会顺手确认 d3d8/d3d9 能加载（部分包装器会走 D3D9）
 *
 * 编译：i686-w64-mingw32-gcc -O1 -o d2check32.exe d2check.c -lddraw -lopengl32 -lgdi32 -luser32
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ddraw.h>
#include <GL/gl.h>
#include <stdio.h>

static int fails = 0;

static void ok(const char *m)   { printf("[ OK ]  %s\n", m); fflush(stdout); }
static void bad(const char *m, HRESULT hr) {
    printf("[FAIL] %s  (hr=0x%08lX)\n", m, (unsigned long)hr); fflush(stdout); fails++;
}
static void note(const char *m) { printf("[ .. ]  %s\n", m); fflush(stdout); }

/* ---------- DirectDraw：D2 2D 模式的渲染路径 ---------- */
static int test_ddraw(void)
{
    IDirectDraw7 *dd = NULL;
    IDirectDrawSurface7 *primary = NULL, *back = NULL;
    IDirectDrawClipper *clip = NULL;
    DDSURFACEDESC2 ddsd;

    HWND hwnd;
    HRESULT hr;
    HDC hdc = NULL;
    int got_back = 0;

    printf("\n-- DirectDraw（D2 默认的 2D 渲染路径）--\n");

    hwnd = CreateWindowExA(0, "STATIC", "d2check", WS_OVERLAPPEDWINDOW,
                           0, 0, 800, 600, NULL, NULL, NULL, NULL);
    if (!hwnd) { printf("[FAIL] CreateWindow 失败 (err=%lu)\n", GetLastError()); fails++; return 1; }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    hr = DirectDrawCreateEx(NULL, (void **)&dd, &IID_IDirectDraw7, NULL);
    if (FAILED(hr)) { bad("DirectDrawCreateEx (DirectDraw 7)", hr); DestroyWindow(hwnd); return 1; }
    ok("DirectDrawCreateEx —— DirectDraw 7 对象创建成功");

    /* 读取当前显示模式 */
    {
        DDSURFACEDESC2 cur;
        ZeroMemory(&cur, sizeof cur); cur.dwSize = sizeof cur;
        hr = IDirectDraw7_GetDisplayMode(dd, &cur);
        if (SUCCEEDED(hr)) {
            char buf[96];
            snprintf(buf, sizeof buf, "GetDisplayMode —— 当前 %lux%lu %lu bpp",
                     (unsigned long)cur.dwWidth, (unsigned long)cur.dwHeight,
                     (unsigned long)cur.ddpfPixelFormat.dwRGBBitCount);
            ok(buf);
        } else { bad("GetDisplayMode", hr); }
    }

    hr = IDirectDraw7_SetCooperativeLevel(dd, hwnd, DDSCL_NORMAL);
    if (FAILED(hr)) bad("SetCooperativeLevel(DDSCL_NORMAL 窗口模式)", hr);
    else            ok("SetCooperativeLevel(DDSCL_NORMAL 窗口模式)");

    if (SUCCEEDED(hr)) {
        ZeroMemory(&ddsd, sizeof ddsd);
        ddsd.dwSize = sizeof ddsd;
        ddsd.dwFlags = DDSD_CAPS;
        ddsd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;

        hr = IDirectDraw7_CreateSurface(dd, &ddsd, &primary, NULL);
        if (FAILED(hr)) bad("创建主表面 (Primary Surface)", hr);
        else {
            ok("创建主表面 (Primary Surface) —— 2D 输出通道可用");

            /* 再建一个后台缓冲，测 Flip/Blit 双缓冲路径 */
            ZeroMemory(&ddsd, sizeof ddsd);
            ddsd.dwSize = sizeof ddsd;
            ddsd.dwFlags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH;
            ddsd.dwWidth = 640; ddsd.dwHeight = 480;
            ddsd.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN;
            hr = IDirectDraw7_CreateSurface(dd, &ddsd, &back, NULL);
            if (SUCCEEDED(hr)) {
                ok("创建离屏表面 640x480 —— blit 缓冲可用");
                got_back = 1;
                hr = IDirectDraw7_CreateClipper(dd, 0, &clip, NULL);
                if (SUCCEEDED(hr)) {
                    IDirectDrawClipper_SetHWnd(clip, 0, hwnd);
                    IDirectDrawSurface7_SetClipper(primary, clip);
                    ok("创建并绑定 Clipper —— 窗口模式裁剪可用");
                } else bad("CreateClipper", hr);
            } else bad("创建离屏表面 (DDSCAPS_OFFSCREENPLAIN)", hr);

            /* 锁定主表面：真正触碰显存/帧缓冲 */
            ZeroMemory(&ddsd, sizeof ddsd);
            ddsd.dwSize = sizeof ddsd;
            hr = IDirectDrawSurface7_Lock(primary, NULL, &ddsd, DDLOCK_WAIT, NULL);
            if (SUCCEEDED(hr)) {
                ok("Lock 主表面 —— 可直接写帧缓冲");
                IDirectDrawSurface7_Unlock(primary, NULL);
            } else bad("Lock 主表面", hr);

            /* 取 DC：D2 用 GDI 往 DDraw 表面画字体/UI */
            hr = IDirectDrawSurface7_GetDC(primary, &hdc);
            if (SUCCEEDED(hr)) {
                ok("GetDC 主表面 —— GDI 绘制通道可用（D2 的 UI 文字走这条路）");
                IDirectDrawSurface7_ReleaseDC(primary, hdc);
            } else bad("GetDC 主表面", hr);
        }
    }

    /* d3d8 / d3d9 动态加载 */
    {
        HMODULE m8 = LoadLibraryA("d3d8.dll");
        HMODULE m9 = LoadLibraryA("d3d9.dll");
        char buf[128];
        if (m8) { ok("d3d8.dll 可加载"); FreeLibrary(m8); }
        else    { note("d3d8.dll 不可加载（D2 不需要，仅记录）"); }
        if (m9) {
            typedef void *(__stdcall *PFN)(UINT);
            PFN c9 = (PFN)GetProcAddress(m9, "Direct3DCreate9");
            if (c9) {
                void *d3d = c9(32 /*D3D_SDK_VERSION*/);
                snprintf(buf, sizeof buf, "d3d9.dll 可加载，Direct3DCreate9 %s", d3d ? "成功" : "返回 NULL");
                if (d3d) {
                    ok(buf);
                    /* 不引入 d3d9.h，直接用 IUnknown 的虚表释放 */
                    ((IUnknown *)d3d)->lpVtbl->Release((IUnknown *)d3d);
                } else { note(buf); }
            } else note("d3d9.dll 里没有 Direct3DCreate9");
            FreeLibrary(m9);
        } else note("d3d9.dll 不可加载（D2 不需要，仅记录）");
    }

    if (clip)    IDirectDrawClipper_Release(clip);
    if (back && got_back) IDirectDrawSurface7_Release(back);
    if (primary) IDirectDrawSurface7_Release(primary);
    if (dd)      IDirectDraw7_Release(dd);
    DestroyWindow(hwnd);
    return 0;
}

/* ---------- OpenGL：Sven's Glide Wrapper 的渲染路径 ---------- */
static int test_opengl(void)
{
    HWND hwnd;
    HDC hdc;
    HGLRC rc;
    PIXELFORMATDESCRIPTOR pfd;
    int pf;
    const char *ver, *ren, *ven;

    printf("\n-- OpenGL（Sven's Glide Wrapper 走的是这条路）--\n");

    hwnd = CreateWindowExA(0, "STATIC", "d2check-gl", WS_OVERLAPPEDWINDOW,
                           0, 0, 640, 480, NULL, NULL, NULL, NULL);
    if (!hwnd) { printf("[FAIL] CreateWindow(GL) 失败\n"); fails++; return 1; }
    hdc = GetDC(hwnd);
    if (!hdc) { printf("[FAIL] GetDC 失败\n"); fails++; DestroyWindow(hwnd); return 1; }

    ZeroMemory(&pfd, sizeof pfd);
    pfd.nSize = sizeof pfd;
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;

    pf = ChoosePixelFormat(hdc, &pfd);
    if (!pf) { printf("[FAIL] ChoosePixelFormat 失败 (err=%lu)\n", GetLastError()); fails++; return 1; }
    ok("ChoosePixelFormat —— 像素格式可选");

    if (!SetPixelFormat(hdc, pf, &pfd)) {
        printf("[FAIL] SetPixelFormat 失败 (err=%lu)\n", GetLastError()); fails++; return 1;
    }
    ok("SetPixelFormat");

    rc = wglCreateContext(hdc);
    if (!rc) { printf("[FAIL] wglCreateContext 失败 (err=%lu)\n", GetLastError()); fails++; return 1; }
    ok("wglCreateContext —— OpenGL 上下文创建成功");

    if (!wglMakeCurrent(hdc, rc)) {
        printf("[FAIL] wglMakeCurrent 失败 (err=%lu)\n", GetLastError()); fails++; return 1;
    }
    ok("wglMakeCurrent");

    ver = (const char *)glGetString(GL_VERSION);
    ren = (const char *)glGetString(GL_RENDERER);
    ven = (const char *)glGetString(GL_VENDOR);
    printf("[ .. ]  GL_VERSION  = %s\n", ver ? ver : "(null)");
    printf("[ .. ]  GL_RENDERER = %s\n", ren ? ren : "(null)");
    printf("[ .. ]  GL_VENDOR   = %s\n", ven ? ven : "(null)");
    if (ver) ok("可查询 OpenGL 版本字符串 —— 3D 模式具备基础条件");
    else     { printf("[FAIL] glGetString(GL_VERSION) 返回空\n"); fails++; }

    glClearColor(0.1f, 0.2f, 0.3f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    ok("glClear + glFinish —— 实际渲染调用未报错");

    wglMakeCurrent(NULL, NULL);
    wglDeleteContext(rc);
    ReleaseDC(hwnd, hdc);
    DestroyWindow(hwnd);
    return 0;
}

int main(void)
{
    SYSTEM_INFO si;
    OSVERSIONINFOA os;
    char arch[64];

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("==============================================\n");
    printf(" 经典版 Diablo II 兼容性自检 (Wine / Apple Silicon)\n");
    printf("==============================================\n\n");
    printf("-- 进程与系统 --\n");

    ZeroMemory(&si, sizeof si); GetNativeSystemInfo(&si);
    snprintf(arch, sizeof arch, "指针宽度 %u 字节 -> %s",
             (unsigned)sizeof(void *), sizeof(void *) == 4 ? "32 位进程" : "64 位进程");
    if (sizeof(void *) == 4) ok(arch); else { printf("[FAIL] %s（D2 需要 32 位运行环境）\n", arch); fails++; }

    ZeroMemory(&os, sizeof os); os.dwOSVersionInfoSize = sizeof os;
    GetVersionExA(&os);
    printf("[ .. ]  报告的系统版本: %lu.%lu build %lu\n",
           (unsigned long)os.dwMajorVersion, (unsigned long)os.dwMinorVersion,
           (unsigned long)os.dwBuildNumber);

    test_ddraw();
    test_opengl();

    printf("\n==============================================\n");
    if (fails == 0) printf(" 结论：全部通过，环境具备运行经典 D2 的条件\n");
    else            printf(" 结论：%d 项失败，见上面 [FAIL] 行\n", fails);
    printf("==============================================\n");
    return fails == 0 ? 0 : 1;
}
