#!/usr/bin/env bash
set -euo pipefail
MESA="${MESA:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mesa}"
BUILD="${BUILD:-$MESA/build-dzn}"
ICD="$BUILD/src/microsoft/vulkan/dzn_devenv_icd.x86_64.json"
usage() {
  cat <<'EOF'
用法:
  ./vkmark.sh deps          安装 apt 依赖
  ./vkmark.sh clone         缺少 Mesa 源码时拉取
  ./vkmark.sh build         构建 Mesa Dozen/DZN
  ./vkmark.sh env           打印当前 shell 可用的环境变量
  ./vkmark.sh run <命令...> 通过 DZN 运行指定命令
  ./vkmark.sh test          通过 DZN 运行 vulkaninfo 和完整 vkmark
  ./vkmark.sh all           deps + clone + build + test
EOF
}
deps() {
  sudo apt-get install -y build-essential git meson ninja-build pkg-config cmake bison flex python3 python3-mako python3-packaging python3-yaml clang-21 llvm-21-dev libclang-21-dev libclang-cpp21-dev llvm-spirv-21 libllvmspirvlib-21-dev libclc-21-dev glslang-tools spirv-tools spirv-tools-dev directx-headers-dev libdrm-dev libelf-dev libudev-dev libunwind-dev libzstd-dev libdisplay-info-dev vulkan-tools vkmark libx11-dev libx11-xcb-dev libxext-dev libxdamage-dev libxfixes-dev libxrandr-dev libxshmfence-dev libxcb1-dev libxcb-dri3-dev libxcb-keysyms1-dev libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libwayland-dev libwayland-egl-backend-dev wayland-protocols
}
clone_mesa() {
  [ -d "$MESA/.git" ] && { printf 'Mesa 已存在: %s\n' "$MESA"; return; }
  mkdir -p "$(dirname "$MESA")"
  git clone --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git "$MESA"
}
build_dzn() {
  clone_mesa
  meson setup $([ ! -d "$BUILD" ] || printf %s --wipe) "$BUILD" "$MESA" -Dvulkan-drivers=microsoft-experimental -Dgallium-drivers= -Dplatforms=x11,wayland -Dllvm=enabled -Dshared-llvm=enabled -Dmicrosoft-clc=enabled -Dspirv-to-dxil=true
  ninja -C "$BUILD" src/microsoft/vulkan/libvulkan_dzn.so src/microsoft/vulkan/dzn_devenv_icd.x86_64.json
}
print_env() {
  printf 'export LD_LIBRARY_PATH=%q\nexport VK_DRIVER_FILES=%q\n' "/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$ICD"
}
run_dzn() {
  [ -f "$ICD" ] || { printf '缺少 DZN ICD: %s\n请先运行: %s build\n' "$ICD" "$0" >&2; exit 1; }
  LD_LIBRARY_PATH="/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" VK_DRIVER_FILES="$ICD" "$@"
}
test_dzn() {
  run_dzn vulkaninfo --summary
  echo
  run_dzn vkmark --winsys xcb --present-mode immediate
}
case "${1:-help}" in
  deps) deps ;;
  clone) clone_mesa ;;
  build) build_dzn ;;
  env) print_env ;;
  run) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; run_dzn "$@" ;;
  test) test_dzn ;;
  all) deps; build_dzn; test_dzn ;;
  -h|--help|help) usage ;;
  *) printf '未知命令: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac
