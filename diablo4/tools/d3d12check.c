/* d3d12check.c — 验证本机 Wine 是否具备 D4 需要的 DX12 / DXGI 能力
 *
 * D4 是 DX12 游戏。Wine 11.9 走 MoltenVK（Vulkan），DX12 需要 vkd3d 或 D3DMetal。
 * 这个程序直接把 DXGI 适配器枚举和 D3D12CreateDevice 的结果打出来。
 *
 * 编译（D4 是 64 位）：
 *   x86_64-w64-mingw32-gcc -O1 -o d3d12check64.exe d3d12check.c -ld3d12 -ldxgi -luuid
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dxgi.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <stdio.h>

static int fails = 0;
static void ok(const char *m)  { printf("[ OK ]  %s\n", m); fflush(stdout); }
static void bad(const char *m, HRESULT hr) {
    printf("[FAIL]  %s  (hr=0x%08lX)\n", m, (unsigned long)hr); fflush(stdout); fails++;
}
static void note(const char *m) { printf("[ .. ]  %s\n", m); fflush(stdout); }

int main(void)
{
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    ID3D12Device *device = NULL;
    HRESULT hr;
    UINT i;

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== DX12 / DXGI 能力检测（D4 需要 DX12）===\n");
    printf("进程位宽: %u 字节 (%s)\n\n", (unsigned)sizeof(void *),
           sizeof(void *) == 8 ? "64 位" : "32 位");

    /* 1. DXGI 工厂 */
    hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
    if (FAILED(hr)) { bad("CreateDXGIFactory1", hr); return 1; }
    ok("CreateDXGIFactory1 —— DXGI 可用");

    /* 2. 枚举适配器 */
    for (i = 0; ; i++) {
        hr = IDXGIFactory1_EnumAdapters1(factory, i, &adapter);
        if (hr == DXGI_ERROR_NOT_FOUND) break;
        if (FAILED(hr)) { bad("EnumAdapters1", hr); break; }
        {
            DXGI_ADAPTER_DESC1 desc;
            if (SUCCEEDED(IDXGIAdapter1_GetDesc1(adapter, &desc))) {
                char buf[320];
                snprintf(buf, sizeof buf, "适配器[%u]: %ls  (显存 %llu MB, 软件=%s)",
                         i, desc.Description,
                         (unsigned long long)(desc.DedicatedVideoMemory / (1024 * 1024)),
                         (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) ? "是" : "否");
                ok(buf);
            }
        }
        IDXGIAdapter1_Release(adapter);
        adapter = NULL;
    }
    if (i == 0) { bad("EnumAdapters1 没有找到任何适配器", E_FAIL); }

    /* 3. D3D12 设备 —— D4 的核心依赖 */
    note("尝试 D3D12CreateDevice(FL_12_0) …");
    hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_12_0, &IID_ID3D12Device, (void **)&device);
    if (SUCCEEDED(hr)) {
        ok("D3D12CreateDevice(12_0) 成功 —— DX12 可用，D4 具备渲染前提");
    } else {
        bad("D3D12CreateDevice(12_0)", hr);
        note("退一步试 11_0 …");
        hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
        if (SUCCEEDED(hr)) ok("D3D12CreateDevice(11_0) 成功（仅 11_0 特性级别）");
        else bad("D3D12CreateDevice(11_0)", hr);
    }

    if (device) {
        D3D12_FEATURE_DATA_FEATURE_LEVELS fls;
        D3D_FEATURE_LEVEL levels[3] = { D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_0 };
        fls.pFeatureLevelsRequested = levels;
        fls.NumFeatureLevels = 3;
        fls.MaxSupportedFeatureLevel = (D3D_FEATURE_LEVEL)0;
        hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_FEATURE_LEVELS,
                                              &fls, sizeof fls);
        if (SUCCEEDED(hr)) {
            char buf[128];
            const char *nm = fls.MaxSupportedFeatureLevel == D3D_FEATURE_LEVEL_12_1 ? "12_1" :
                             fls.MaxSupportedFeatureLevel == D3D_FEATURE_LEVEL_12_0 ? "12_0" : "更低";
            snprintf(buf, sizeof buf, "最高支持特性级别: %s", nm);
            (fls.MaxSupportedFeatureLevel >= D3D_FEATURE_LEVEL_12_0) ? ok(buf) : note(buf);
        }
        ID3D12Device_Release(device);
    }

    if (factory) IDXGIFactory1_Release(factory);

    printf("\n=== 结论 ===\n");
    if (fails == 0) printf("DX12 可用 —— D4 的渲染前提满足\n");
    else            printf("DX12 不可用（%d 项失败）—— 需要 vkd3d/DXVK 或 D3DMetal 才能跑 D4\n", fails);
    return fails == 0 ? 0 : 1;
}
