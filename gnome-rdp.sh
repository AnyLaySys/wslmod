#!/usr/bin/env bash
set -euo pipefail
RUNUSER="$(id -un)"
PORT="${PORT:-3390}"
RDPHOST="${RDPHOST:-127.0.0.1}"
GRDUSER="${GRDUSER:-$RUNUSER}"
ACCEL="${ACCEL:-auto}"
MONITOR="${MONITOR:-1920x1080}"
WLDISP="${WLDISP:-gnome-rdp}"
DZNICD="${DZNICD:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mesa/build-dzn/src/microsoft/vulkan/dzn_devenv_icd.x86_64.json}"
CFGDIR="$HOME/.config/gnome-remote-desktop"
PASSFILE="$CFGDIR/headless-rdp-password"
CERTFILE="$CFGDIR/rdp-tls.crt"
KEYFILE="$CFGDIR/rdp-tls.key"
RDPFILE="$CFGDIR/gnome-rdp.rdp"
SESSION="gnome-session@ubuntu.target"
SHELLSVC="org.gnome.Shell@ubuntu.service"
GRDSVC="gnome-remote-desktop-headless.service"
usage() {
  cat <<EOF
GNOME RDP Shell       26.7.7
Windows远程桌面连接GNOME RDP
用法:
  ./gnome-rdp.sh deps     安装完整 ubuntu-desktop + GNOME Remote Desktop
  ./gnome-rdp.sh cfg      配置 GNOME 官方 RDP(headless user daemon)
  ./gnome-rdp.sh start    启动 GNOME RDP 并打开 Windows 远程桌面
  ./gnome-rdp.sh status   查看状态、端口和凭据文件
  ./gnome-rdp.sh open     cfg + start
  ./gnome-rdp.sh password 重新生成 GRD RDP 密码
  ./gnome-rdp.sh all      deps + cfg + start + status
变量:
  PORT=$PORT               RDP 监听端口
  RDPHOST=$RDPHOST       Windows 侧连接地址
  GRDUSER=<当前用户>      RDP 凭据用户名,默认当前 Linux 用户
  GRDPASS=...             指定 RDP 凭据密码；不指定则自动生成并保存
  MONITOR=$MONITOR       headless GNOME 虚拟显示器大小
  WLDISP=$WLDISP        Wayland display 名称
  ACCEL=$ACCEL              auto/1/0,自动启用 WSL D3D12 Mesa 应用环境
EOF
}
deps() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop gnome-remote-desktop gdm3 openssl
}
ensure_password() {
  mkdir -p "$CFGDIR"
  chmod 700 "$CFGDIR"
  if [ -n "${GRDPASS:-}" ]; then
    printf '%s' "$GRDPASS" > "$PASSFILE"
  elif [ ! -s "$PASSFILE" ]; then
    openssl rand -hex 12 > "$PASSFILE"
  fi
  chmod 600 "$PASSFILE"
}
ensure_certificate() {
  mkdir -p "$CFGDIR"
  chmod 700 "$CFGDIR"
  if [ ! -s "$CERTFILE" ] || [ ! -s "$KEYFILE" ]; then
    openssl req -x509 -nodes -newkey rsa:3072 -keyout "$KEYFILE" -out "$CERTFILE" -days 825 -subj "/CN=$(hostname)-gnome-remote-desktop" >/dev/null 2>&1
  fi
  chmod 600 "$CERTFILE" "$KEYFILE"
}
stop_system_login_stack() {
  sudo systemctl disable --now gnome-remote-desktop.service gdm3 2>/dev/null || true
}
disable_old_shell_service() {
  systemctl --user disable --now gnome-shell-headless-rdp.service 2>/dev/null || true
}
d3d12_accel_available() {
  [ "$ACCEL" != "0" ] &&
    [ -e /dev/dxg ] &&
    [ -r /usr/lib/wsl/lib/libd3d12.so ] &&
    [ -e /usr/lib/x86_64-linux-gnu/dri/d3d12_dri.so ]
}
accel_env_assignments() {
  d3d12_accel_available || return 0
  echo "LD_LIBRARY_PATH=/usr/lib/wsl/lib"
  echo "LIBGL_ALWAYS_SOFTWARE=0"
  echo "MESA_LOADER_DRIVER_OVERRIDE=d3d12"
  echo "GALLIUM_DRIVER=d3d12"
  if [ -s "$DZNICD" ]; then
    echo "VK_DRIVER_FILES=$DZNICD"
  fi
}
write_systemd_environment_lines() {
  accel_env_assignments | while IFS= read -r assignment; do
    echo "Environment=$assignment"
  done
}
set_session_environment() {
  local activation_vars
  local dbus_env
  local session_env
  systemctl --user unset-environment DISPLAY XAUTHORITY LD_LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER VK_DRIVER_FILES 2>/dev/null || true
  session_env=(
    XDG_SESSION_TYPE=wayland
    XDG_SESSION_DESKTOP=ubuntu
    XDG_CURRENT_DESKTOP=ubuntu:GNOME
    DESKTOP_SESSION=ubuntu
    GDMSESSION=ubuntu
    GNOME_SHELL_SESSION_MODE=ubuntu
    WAYLAND_DISPLAY="$WLDISP"
  )
  systemctl --user set-environment "${session_env[@]}"
  if d3d12_accel_available; then
    while IFS= read -r assignment; do
      systemctl --user set-environment "$assignment"
    done < <(accel_env_assignments)
  fi
  activation_vars=(DISPLAY XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP DESKTOP_SESSION GDMSESSION GNOME_SHELL_SESSION_MODE WAYLAND_DISPLAY)
  if d3d12_accel_available; then
    activation_vars+=(LD_LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER)
    [ -s "$DZNICD" ] && activation_vars+=(VK_DRIVER_FILES)
  fi
  dbus_env=(
    env
    DISPLAY=
    XDG_SESSION_TYPE=wayland
    XDG_SESSION_DESKTOP=ubuntu
    XDG_CURRENT_DESKTOP=ubuntu:GNOME
    DESKTOP_SESSION=ubuntu
    GDMSESSION=ubuntu
    GNOME_SHELL_SESSION_MODE=ubuntu
    WAYLAND_DISPLAY="$WLDISP"
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/usr/lib/wsl/lib}"
    LIBGL_ALWAYS_SOFTWARE=0
    MESA_LOADER_DRIVER_OVERRIDE=d3d12
    GALLIUM_DRIVER=d3d12
    VK_DRIVER_FILES="$DZNICD"
    dbus-update-activation-environment
    --systemd
  )
  "${dbus_env[@]}" "${activation_vars[@]}" >/dev/null 2>&1 || true
}
ensure_headless_session_override() {
  mkdir -p "$HOME/.config/systemd/user/$SHELLSVC.d"
  cat > "$HOME/.config/systemd/user/$SHELLSVC.d/10-headless-rdp.conf" <<EOF
[Unit]
AssertEnvironment=
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_SESSION_DESKTOP=ubuntu
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=DESKTOP_SESSION=ubuntu
Environment=GDMSESSION=ubuntu
Environment=GNOME_SHELL_SESSION_MODE=ubuntu
$(write_systemd_environment_lines)
UnsetEnvironment=DISPLAY WAYLAND_DISPLAY
ExecStart=
ExecStart=/usr/bin/gnome-shell --wayland --headless --no-x11 --wayland-display=$WLDISP --mode=%i
EOF
  systemctl --user daemon-reload
}
ensure_grd_override() {
  mkdir -p "$HOME/.config/systemd/user/$GRDSVC.d"
  cat > "$HOME/.config/systemd/user/$GRDSVC.d/10-d3d12-accel.conf" <<EOF
[Service]
UnsetEnvironment=LD_LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER VK_DRIVER_FILES
EOF
  systemctl --user daemon-reload
}
configure_desktop_shell() {
  gsettings set org.gnome.shell enabled-extensions "['ubuntu-dock@ubuntu.com', 'ubuntu-appindicators@ubuntu.com', 'ding@rastersoft.com', 'tiling-assistant@ubuntu.com']" || true
  gsettings set org.gnome.shell disable-user-extensions false || true
  if gsettings writable org.gnome.shell.extensions.dash-to-dock dock-fixed >/dev/null 2>&1; then
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide false
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false
    gsettings set org.gnome.shell.extensions.dash-to-dock manualhide false
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'
    gsettings set org.gnome.shell.extensions.dash-to-dock extend-height true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-running true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-show-apps-button true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-trash true
    gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 48
    gsettings set org.gnome.shell.extensions.dash-to-dock disable-overview-on-startup true
  fi
}
write_rdp_file() {
  mkdir -p "$CFGDIR"
  cat > "$RDPFILE" <<EOF
full address:s:$RDPHOST:$PORT
username:s:$GRDUSER
prompt for credentials:i:0
enablecredsspsupport:i:1
authentication level:i:0
screen mode id:i:1
desktopwidth:i:${MONITOR%x*}
desktopheight:i:${MONITOR#*x}
smart sizing:i:1
dynamic resolution:i:1
use multimon:i:0
redirectclipboard:i:1
audiomode:i:0
EOF
}
cfg() {
  ensure_password
  ensure_certificate
  stop_system_login_stack
  sudo loginctl enable-linger "$RUNUSER"
  disable_old_shell_service
  set_session_environment
  ensure_headless_session_override
  ensure_grd_override
  configure_desktop_shell
  grdctl --headless rdp set-port "$PORT"
  grdctl --headless rdp disable-port-negotiation
  grdctl --headless rdp set-auth-methods credentials
  grdctl --headless rdp set-credentials "$GRDUSER" "$(head -n 1 "$PASSFILE")"
  grdctl --headless rdp set-tls-cert "$CERTFILE"
  grdctl --headless rdp set-tls-key "$KEYFILE"
  grdctl --headless rdp disable-view-only
  grdctl --headless rdp enable
  write_rdp_file
}
wait_for_wayland_display() {
  local socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WLDISP"
  for _ in $(seq 1 60); do
    [ -S "$socket" ] && return 0
    sleep 1
  done
  echo "headless GNOME Shell 没有创建 Wayland socket: $socket" >&2
  systemctl --user --no-pager --full status "$SESSION" "$SHELLSVC" >&2 || true
  journalctl --user -u "$SHELLSVC" -n 120 --no-pager >&2 || true
  return 1
}
wait_for_rdp_port() {
  for _ in $(seq 1 60); do
    if ss -ltn | grep -q ":$PORT "; then
      return 0
    fi
    sleep 1
  done
  echo "GNOME Remote Desktop 没有监听端口: $PORT" >&2
  systemctl --user --no-pager --full status "$GRDSVC" >&2 || true
  journalctl --user -u "$GRDSVC" -n 120 --no-pager >&2 || true
  return 1
}
restart_gnome_session() {
  systemctl --user start gnome-session-shutdown.target 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! systemctl --user --quiet is-active "$SHELLSVC"; then
      break
    fi
    sleep 1
  done
  if systemctl --user --quiet is-active "$SHELLSVC"; then
    systemctl --user kill --signal=TERM "$SHELLSVC" 2>/dev/null || true
    sleep 2
  fi
  systemctl --user stop gnome-session-shutdown.target 2>/dev/null || true
  systemctl --user reset-failed "$SESSION" "$SHELLSVC" gnome-session-shutdown.target 2>/dev/null || true
}
start_session() {
  stop_system_login_stack
  disable_old_shell_service
  set_session_environment
  ensure_headless_session_override
  ensure_grd_override
  configure_desktop_shell
  write_rdp_file
  restart_gnome_session
  systemctl --user start "$SESSION"
  wait_for_wayland_display
  systemctl --user enable --now "$GRDSVC"
  systemctl --user restart "$GRDSVC"
  wait_for_rdp_port
}
ensure_windows_interop() {
  if powershell.exe -NoProfile -Command "exit 0" >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -e /proc/sys/fs/binfmt_misc/register ]; then
    sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
  fi
  if [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
    printf ':WSLInterop:M::MZ::/init:PF' | sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null
  elif ! grep -q '^enabled' /proc/sys/fs/binfmt_misc/WSLInterop; then
    echo 1 | sudo tee /proc/sys/fs/binfmt_misc/WSLInterop >/dev/null
  fi
  powershell.exe -NoProfile -Command "exit 0" >/dev/null
}
launch_rdp() {
  store_windows_credentials
  trust_windows_certificate
  powershell.exe -NoProfile -Command "Start-Process mstsc.exe -ArgumentList '$(wslpath -w "$RDPFILE")'"
}
start() {
  start_session
  launch_rdp
}
status() {
  grdctl --headless status --show-credentials || true
  systemctl --user --no-pager --full status "$SESSION" || true
  systemctl --user --no-pager --full status "$SHELLSVC" || true
  systemctl --user --no-pager --full status "$GRDSVC" || true
  systemctl --no-pager --full status gnome-remote-desktop.service gdm3 || true
  ss -ltnp | grep ":$PORT " || true
  echo "Windows 连接地址: $RDPHOST:$PORT"
  echo "RDP 用户名: $GRDUSER"
  if [ -s "$PASSFILE" ]; then
    echo "RDP 密码文件: $PASSFILE"
  fi
  if [ -s "$RDPFILE" ]; then
    echo "Windows RDP 文件: $RDPFILE"
  fi
}
store_windows_credentials() {
  local password
  ensure_windows_interop
  ensure_password
  password="$(head -n 1 "$PASSFILE")"
  cmdkey.exe "/generic:TERMSRV/$RDPHOST" "/user:$GRDUSER" "/pass:$password" >/dev/null
  cmdkey.exe "/generic:TERMSRV/$RDPHOST:$PORT" "/user:$GRDUSER" "/pass:$password" >/dev/null
  if [ "$RDPHOST" != "localhost" ]; then
    cmdkey.exe "/generic:TERMSRV/localhost" "/user:$GRDUSER" "/pass:$password" >/dev/null
    cmdkey.exe "/generic:TERMSRV/localhost:$PORT" "/user:$GRDUSER" "/pass:$password" >/dev/null
  fi
}
trust_windows_certificate() {
  ensure_certificate
  powershell.exe -NoProfile -Command "Import-Certificate -FilePath '$(wslpath -w "$CERTFILE")' -CertStoreLocation Cert:/CurrentUser/Root | Out-Null" >/dev/null 2>&1 || true
}
open_rdp() {
  cfg
  start
}
case "${1:-help}" in
  deps) deps ;;
  cfg) cfg ;;
  start) start ;;
  status) status ;;
  open) open_rdp ;;
  password) rm -f "$PASSFILE"; ensure_password; cfg; store_windows_credentials; status ;;
  all) deps; cfg; start; status ;;
  -h|--help|help) usage ;;
  *) echo "未知命令: $1" >&2; echo >&2; usage >&2; exit 2 ;;
esac