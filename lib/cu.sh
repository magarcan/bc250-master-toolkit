#!/usr/bin/env bash
CU_MANAGER_URL=https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/refs/heads/main/bc250-cu-live-manager.sh
CU_MANAGER=/usr/local/bin/bc250-cu-live-manager
UMR_SRC=https://gitlab.freedesktop.org/tomstdenis/umr.git
bc250_cu_install() { command -v curl >/dev/null 2>&1 || pacman -S --needed --noconfirm curl; curl -fsSL "$CU_MANAGER_URL" -o "$CU_MANAGER"; chmod 755 "$CU_MANAGER"; echo "[ OK ] CU/WGP manager installed: $CU_MANAGER"; }
bc250_umr_install() {
  command -v umr >/dev/null 2>&1 && { echo '[ OK ] UMR already installed'; return 0; }
  echo '[INFO] UMR is not in the enabled CachyOS repositories; building official upstream source.'
  pacman -S --needed --noconfirm git cmake base-devel pciutils libpciaccess libdrm ncurses pkgconf
  local d=/tmp/bc250-umr-build; rm -rf "$d"; git clone --depth 1 "$UMR_SRC" "$d"
  cmake -S "$d" -B "$d/build" -DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON
  cmake --build "$d/build" -j"$(nproc)"; cmake --install "$d/build"
  command -v umr >/dev/null 2>&1 || { echo '[ERR ] UMR was not installed.' >&2; return 1; }
  echo '[ OK ] UMR installed from upstream source.'
}
bc250_cu_status() { [ -x "$CU_MANAGER" ] && echo '[ OK ] CU/WGP manager: installed' || echo '[WARN] CU/WGP manager: missing'; command -v umr >/dev/null 2>&1 && echo '[ OK ] UMR: installed' || echo '[WARN] UMR: missing'; }
