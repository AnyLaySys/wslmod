# WSL DZN Vulkan
在 WSL 中构建 Mesa Dozen/DZN,让 Vulkan 通过 D3D12 使用 Windows 侧 GPU.  
默认不安装系统级 ICD,只通过环境变量临时启用.
### 构建
```bash
./vkmark.sh all
```
使用已有构建测试：
```bash
./vkmark.sh test
./vkmark.sh run vulkaninfo --summary
```
`test` 会通过 XCB 和 immediate present mode 运行完整默认 `vkmark` 测试.  
在当前 shell 启用 DZN：
```bash
eval "$(./vkmark.sh env)"
```
手动构建流程：
```bash
cd mesa
meson setup build-dzn --wipe -Dvulkan-drivers=microsoft-experimental -Dgallium-drivers= -Dplatforms=x11,wayland -Dllvm=enabled -Dshared-llvm=enabled -Dmicrosoft-clc=enabled -Dspirv-to-dxil=true
ninja -C build-dzn src/microsoft/vulkan/libvulkan_dzn.so
ninja -C build-dzn src/microsoft/vulkan/dzn_devenv_icd.x86_64.json
```
### 效果
```text
GPU0:
        apiVersion         = 1.2.354
        driverVersion      = 26.1.99
        vendorID           = 0x10de
        deviceID           = 0x21c4
        deviceType         = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
        deviceName         = Microsoft Direct3D12 (NVIDIA GeForce GTX 1660 SUPER)
        driverID           = DRIVER_ID_MESA_DOZEN
        driverName         = Dozen
        driverInfo         = Mesa 26.2.0-devel (git-8aa0199f35)
        conformanceVersion = 0.0.0.0
        deviceUUID         = 78eed49b-60c3-294b-a297-3bfe5482eee8
        driverUUID         = 1bac3492-446b-aaf9-45a8-7248a58a4c1d

WARNING: dzn is not a conformant Vulkan implementation, testing use only.
=======================================================
    vkmark 2025.01
=======================================================
    Vendor ID:      0x10DE
    Device ID:      0x21C4
    Device Name:    Microsoft Direct3D12 (NVIDIA GeForce GTX 1660 SUPER)
    Driver Version: 109056099
    Device UUID:    5b8ff240c4bcbf49d531f07b94c8d446
=======================================================
[vertex] device-local=true: FPS: 979 FrameTime: 1.021 ms
[vertex] device-local=false: FPS: 935 FrameTime: 1.070 ms
[texture] anisotropy=0: FPS: 927 FrameTime: 1.079 ms
[texture] anisotropy=16: FPS: 954 FrameTime: 1.048 ms
[shading] shading=gouraud: FPS: 973 FrameTime: 1.028 ms
[shading] shading=blinn-phong-inf: FPS: 970 FrameTime: 1.031 ms
[shading] shading=phong: FPS: 960 FrameTime: 1.042 ms
[shading] shading=cel: FPS: 965 FrameTime: 1.036 ms
[effect2d] kernel=edge: FPS: 1002 FrameTime: 0.998 ms
[effect2d] kernel=blur: FPS: 1008 FrameTime: 0.992 ms
[desktop] <default>: FPS: 969 FrameTime: 1.032 ms
[cube] <default>: FPS: 891 FrameTime: 1.122 ms
[clear] <default>: FPS: 751 FrameTime: 1.332 ms
=======================================================
                                   vkmark Score: 944
=======================================================
```
