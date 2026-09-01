#!/usr/bin/env bash

CU_MANAGER_URL=https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/refs/heads/main/bc250-cu-live-manager.sh
CU_MANAGER=/usr/local/bin/bc250-cu-live-manager
UMR_SRC=https://gitlab.freedesktop.org/tomstdenis/umr.git

bc250_umr_present() { command -v umr >/dev/null 2>&1; }

bc250_umr_status() {
  if bc250_umr_present; then
    ok "UMR (User Mode Register debugger): installed ($(command -v umr))"
  else
    warn 'UMR (User Mode Register debugger): missing'
  fi
}

bc250_umr_install() {
  if bc250_umr_present; then
    ok "UMR already installed: $(command -v umr)"
    return 0
  fi
  command -v pacman >/dev/null 2>&1 || die 'pacman was not found; UMR source installation requires CachyOS/Arch.'
  command -v git >/dev/null 2>&1 || pacman -S --needed --noconfirm git || die 'Could not install git.'
  pacman -S --needed --noconfirm cmake base-devel pciutils libpciaccess libdrm ncurses pkgconf || die 'Could not install UMR build dependencies.'
  info 'UMR is not available in the enabled CachyOS/AUR path; downloading the official upstream source.'
  local d
  d=$(mktemp -d /tmp/bc250-umr-build.XXXXXX) || die 'Could not create UMR build directory.'
  git clone --depth 1 "$UMR_SRC" "$d/umr" || { rm -rf "$d"; die 'Could not download UMR source.'; }
  cmake -S "$d/umr" -B "$d/umr/build" -DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON || { rm -rf "$d"; die 'UMR configuration failed.'; }
  cmake --build "$d/umr/build" -j"$(nproc)" || { rm -rf "$d"; die 'UMR build failed.'; }
  cmake --install "$d/umr/build" || { rm -rf "$d"; die 'UMR installation failed.'; }
  rm -rf "$d"
  command -v umr >/dev/null 2>&1 || die 'UMR was built but the installed binary was not found.'
  ok "UMR installed from official upstream source: $(command -v umr)"
}

bc250_cu_install() {
  if ! bc250_umr_present; then
    warn 'UMR is required before installing the BC-250 CU/WGP manager.'
    bc250_umr_install || return 1
  else
    ok "UMR detected: $(command -v umr)"
  fi

  command -v curl >/dev/null 2>&1 || pacman -S --needed --noconfirm curl
  curl -fsSL "$CU_MANAGER_URL" -o "$CU_MANAGER" || die 'Could not download the BC-250 CU/WGP manager.'
  chmod 755 "$CU_MANAGER" || die 'Could not make the BC-250 CU/WGP manager executable.'
  [ -x "$CU_MANAGER" ] || die 'CU/WGP manager was downloaded but is not executable.'
  ok "CU/WGP manager installed: $CU_MANAGER"

  echo
  info 'Launching the BC-250 CU/WGP live manager...'
  "$CU_MANAGER"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    ok 'CU/WGP manager exited normally; returning to the Master Toolkit.'
    return 0
  fi
  warn "CU/WGP manager exited with status $rc; returning to the Master Toolkit."
  return "$rc"
}

bc250_umr_install_if_missing() {
  bc250_umr_present && { ok "UMR already installed: $(command -v umr)"; return 0; }
  bc250_umr_install
}

bc250_cu_status() {
  [ -x "$CU_MANAGER" ] && echo '[ OK ] CU/WGP manager: installed' || echo '[WARN] CU/WGP manager: missing'
  bc250_umr_present && echo "[ OK ] UMR: installed ($(command -v umr))" || echo '[WARN] UMR: missing'
}
