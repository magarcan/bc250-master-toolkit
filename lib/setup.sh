#!/usr/bin/env bash

BC250_BIOS_URL="https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script"
BC250_BIOS_RELEASE_URL="https://github.com/Forbidden-Darkness/AMD-BC-250-UEFI-v2.2-Firmware-Menu-Script/releases/latest"
BC250_KERNEL_REPO_URL="https://github.com/MastaG/linux-cachyos-bc250"
BC250_KERNEL_PACMAN_REPO="https://github.com/MastaG/linux-cachyos-bc250/releases/download/repo"
BC250_PACMAN_CONF="/etc/pacman.conf"

bc250_setup_is_root() { [ "$EUID" -eq 0 ]; }
bc250_setup_require_root() { bc250_setup_is_root && return 0; command -v sudo >/dev/null 2>&1 || die 'sudo is required for this operation.'; sudo -v || die 'Authorization was cancelled.'; sudo "$ROOT/bc250-master-toolkit" __root "$@"; }
bc250_kernel_package_installed() { pacman -Q linux-cachyos-bc250 >/dev/null 2>&1; }
bc250_kernel_active_ok() { uname -r | grep -qi -- 'bc250'; }
bc250_kernel_repo_configured() { grep -qE '^\[bc250-cachyos\][[:space:]]*$' "$BC250_PACMAN_CONF" 2>/dev/null; }
bc250_kernel_repo_configure() {
  bc250_setup_is_root || return 1
  [ -f "$BC250_PACMAN_CONF" ] || die "$BC250_PACMAN_CONF not found."
  bc250_kernel_repo_configured && return 0
  cp -a "$BC250_PACMAN_CONF" "$BC250_PACMAN_CONF.bc250-toolkit.bak" || die 'Could not back up pacman.conf.'
  python3 - "$BC250_PACMAN_CONF" "$BC250_KERNEL_PACMAN_REPO" <<'PY'
import sys
path, server = sys.argv[1:]
s = open(path, encoding='utf-8').read()
block = f"[bc250-cachyos]\nSigLevel = Optional TrustAll\nServer = {server}\n"
if '[cachyos-v3]' in s: s = s.replace('[cachyos-v3]', block + '\n[cachyos-v3]', 1)
else: s = s.rstrip() + '\n\n' + block
open(path, 'w', encoding='utf-8').write(s)
PY
  ok 'BC-250 package repository configured.'
}
bc250_kernel_install() {
  bc250_setup_is_root || die 'Internal error: kernel installation requires root.'
  command -v pacman >/dev/null 2>&1 || die 'pacman was not found; this setup requires Arch/CachyOS.'
  bc250_kernel_repo_configure
  info 'Refreshing package databases and installing the stable BC-250 kernel...'
  pacman -Syu --needed linux-cachyos-bc250 linux-cachyos-bc250-headers || die 'BC-250 kernel installation failed.'
  ok 'linux-cachyos-bc250 and headers installed.'
  echo; warn 'Reboot is required to start the newly installed kernel.'; printf '  Active kernel now : %s\n  Installed kernel  : linux-cachyos-bc250\n' "$(uname -r)"
}
bc250_kernel_setup_menu_action() {
  banner; heading 'Kernel Setup'; echo
  if bc250_kernel_active_ok; then ok "Active kernel: $(uname -r)"; echo; info 'The active kernel already contains the BC-250 marker.'; return 0; fi
  warn "Active kernel: $(uname -r)"; echo
  printf '  Recommended kernel : linux-cachyos-bc250\n  Source repository  : %s\n\n' "$BC250_KERNEL_REPO_URL"
  printf 'This is the stable/default BC-250 kernel published by the project.\nIt includes the BC-250 kernel patches and matching headers.\n\nInstall it now? [Y/n]: '
  read -r answer; case "$answer" in n|N) info 'Kernel installation skipped.'; return 0;; esac
  bc250_setup_require_root kernel-install
}
bc250_bios_setup_menu_action() {
  banner; heading 'BIOS Recommendation'; echo
  if bc250_bios_ok; then ok "BIOS P3.00 detected: $(bc250_bios)"; echo; info 'No BIOS action is required from the toolkit.'; return 0; fi
  warn "Detected BIOS: $(bc250_bios)"; echo
  printf 'Recommended BIOS: P3.00 community BC-250 firmware\nIt provides the 8-core unlock and patched SMU telemetry path.\n\n'
  printf 'The toolkit will NOT flash your BIOS. You must perform the firmware\ninstallation yourself using the project instructions.\n\nFirmware project:\n  %s\n\nLatest release:\n  %s\n\n' "$BC250_BIOS_URL" "$BC250_BIOS_RELEASE_URL"
  printf 'Open the firmware project in your browser? [Y/n]: '; read -r answer
  case "$answer" in n|N) info 'Browser launch skipped.'; return 0;; esac
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$BC250_BIOS_URL" >/dev/null 2>&1 &; ok 'Firmware project opened in the default browser.'; else info "Open this URL manually: $BC250_BIOS_URL"; fi
}
bc250_platform_status_lines() {
  bc250_bios_ok && ok 'BIOS P3.00 — recommended telemetry firmware' || warn "BIOS $(bc250_bios) — recommended P3.00 not detected"
  bc250_kernel_ok && ok "Kernel $(uname -r) — BC-250 kernel active" || warn "Kernel $(uname -r) — BC-250 kernel not active"
  [ "$(bc250_cpu_cores)" -ge 8 ] 2>/dev/null && ok "CPU topology: $(bc250_cpu_cores) cores / $(bc250_cpu_threads) threads" || warn "CPU topology: $(bc250_cpu_cores) cores / $(bc250_cpu_threads) threads"
}
[ -r "$ROOT/lib/gpu_status_fix.sh" ] && source "$ROOT/lib/gpu_status_fix.sh"
[ -r "$ROOT/lib/ui_overrides.sh" ] && source "$ROOT/lib/ui_overrides.sh"
