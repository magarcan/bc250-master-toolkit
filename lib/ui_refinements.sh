#!/usr/bin/env bash

# Canonical UI status colors. All interactive status messages must use these
# helpers instead of embedding literal [ OK ]/[WARN]/[ERR ] markers.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  UI_RESET=$'\033[0m'; UI_GREEN=$'\033[1;32m'; UI_YELLOW=$'\033[1;33m'; UI_RED=$'\033[1;31m'; UI_CYAN=$'\033[1;36m'
else
  UI_RESET=''; UI_GREEN=''; UI_YELLOW=''; UI_RED=''; UI_CYAN=''
fi
ok()   { printf '  %s[ OK ]%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
warn() { printf '  %s[WARN]%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*"; }
info() { printf '  %s[INFO]%s %s\n' "$UI_CYAN" "$UI_RESET" "$*"; }
die()  { printf '  %s[ERR ]%s %s\n' "$UI_RED" "$UI_RESET" "$*" >&2; return 1; }

ui_preflight() {
  ui_banner; printf 'Preflight / Platform Validation\n\n'
  local card; card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" != card* ]]; then warn 'AMD BC-250 GPU was not detected.'; return 1; fi
  ok 'AMD BC-250 detected (PCI 1002:13fe).'
  printf '\n  OS              : %s\n  Kernel          : %s\n  BIOS            : %s\n  CPU             : %sC / %sT\n  CPU driver      : %s\n  CPU governor    : %s\n  GPU             : %s\n' "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")" "$(uname -r)" "$(bc250_bios)" "$(bc250_cpu_cores)" "$(bc250_cpu_threads)" "$(bc250_cpu_driver)" "$(bc250_cpu_governor)" "$card"
  heading 'Platform'
  local missing=() threads cores bios_ok kernel_ok; bios_ok=0; kernel_ok=0
  if bc250_bios_ok; then bios_ok=1; ok "BIOS $(bc250_bios) detected"; else warn "BIOS $(bc250_bios) — P3.00 recommended"; missing+=("BIOS"); fi
  if bc250_kernel_ok; then kernel_ok=1; ok 'CachyOS BC-250 kernel detected'; else warn "Kernel $(uname -r) — BC-250 kernel recommended"; missing+=("Kernel"); fi
  cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
  if [ "$cores" -ge 8 ] && [ "$threads" -ge 16 ]; then ok "CPU topology: ${cores}C / ${threads}T — all cores enabled"; elif [ "$cores" -ge 6 ] && [ "$threads" -ge 12 ]; then warn "CPU topology: ${cores}C / ${threads}T — Core Unlock may be disabled in BIOS"; missing+=("CPU Core Unlock in BIOS"); else warn "CPU topology: ${cores}C / ${threads}T — unexpected BC-250 topology"; missing+=("CPU topology"); fi
  if [ "$bios_ok" -eq 1 ] && [ "$kernel_ok" -eq 1 ]; then ok 'ACPI: native BC-250 support — no ACPI override required'; else warn 'ACPI: native BC-250 support cannot be validated until BIOS and kernel are correct'; missing+=("Native BC-250 ACPI support"); fi
  heading 'Software & Telemetry'
  command -v cpupower >/dev/null 2>&1 && ok 'cpupower available' || { warn 'cpupower missing'; missing+=("cpupower"); }
  command -v vulkaninfo >/dev/null 2>&1 && ok 'vulkaninfo available' || { warn 'vulkaninfo missing'; missing+=("vulkaninfo"); }
  [ -x /usr/bin/cyan-skillfish-governor-smu ] && ok 'Cyan-Skillfish binary installed' || { warn 'Cyan-Skillfish governor missing'; missing+=("GPU governor"); }
  [ -f /etc/cyan-skillfish-governor-smu/config.toml ] && ok 'Cyan-Skillfish configuration present' || { warn 'Cyan-Skillfish configuration missing'; missing+=("GPU governor configuration"); }
  bc250_governor_ok && ok 'GPU governor service active' || { warn 'GPU governor service inactive'; missing+=("GPU governor service"); }
  bc250_telemetry_ok && ok 'GPU telemetry interfaces available' || { warn 'GPU telemetry interfaces incomplete'; missing+=("GPU telemetry"); }
  [ -r "/sys/class/drm/$card/device/pp_dpm_sclk" ] && ok 'GPU DPM interface available' || { warn 'GPU DPM interface unavailable'; missing+=("GPU DPM"); }
  [ -r "/sys/class/drm/$card/device/mem_info_vram_total" ] && ok 'VRAM telemetry available' || { warn 'VRAM telemetry unavailable'; missing+=("VRAM telemetry"); }
  heading 'CU / WGP'
  [ -x /usr/local/bin/bc250-cu-live-manager ] && ok 'cu-live manager available' || { warn 'cu-live manager missing'; missing+=("CU/WGP manager"); }
  bc250_umr_present && ok 'UMR available' || { warn 'UMR missing'; missing+=("UMR"); }
  if [ "${#missing[@]}" -eq 0 ]; then printf '\n'; ok 'Platform validation: PASS'; printf '        BIOS, kernel, CPU topology, ACPI and toolkit dependencies are ready.\n'; info 'No ACPI override or software core-unlock action is required.'; return 0; fi
  printf '\n'; warn "Platform validation: INCOMPLETE (${#missing[@]} item(s) require attention)"; printf '\nConfigure missing components now? [Y/n]: '; local answer; read -r answer
  case "${answer,,}" in n) info 'No setup changes requested.';; *) ui_preflight_install_menu;; esac
}

ui_extras_status() {
  ui_banner; printf 'System Extras\n\n'; heading 'Current state'
  local zswap zram conf rdseed mitigations swapfile
  zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N); zram=$([ -e /dev/zram0 ] && echo present || echo not-exposed); conf=$(bc250_boot_conf 2>/dev/null || true); swapfile=$(swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {print; exit}')
  printf '  Swapfile             '; if [ -n "$swapfile" ]; then ok "Enabled — $swapfile"; else warn 'Not configured'; fi
  printf '  ZRAM                 '; if [ "$zram" = present ]; then ok 'Active'; else info 'Not exposed'; fi
  printf '  ZSWAP                '; if [ "$zswap" = Y ]; then ok 'Enabled'; else warn 'Disabled'; fi
  printf '  Boot configuration   %s\n' "${conf:-not found}"
  rdseed=default; mitigations=default
  if [ -n "$conf" ]; then grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed=hidden; grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations=disabled; fi
  printf '  RDSEED warning       '; [ "$rdseed" = hidden ] && ok 'Hidden' || info 'Default'
  printf '  CPU mitigations      '; [ "$mitigations" = disabled ] && warn 'Disabled' || info 'Default'
}

ui_extras() {
  while true; do
    ui_extras_status; printf '\n'; heading 'Available actions'
    printf '[ 1] Enable Swap          — Persistent swapfile (16G default)\n'
    printf '[ 2] Enable ZSWAP         — Disable systemd ZRAM and enable compressed swap\n'
    printf '[ 3] Hide RDSEED Warning  — Set boot loglevel=0\n'
    printf '[ 4] Disable Mitigations  — Add mitigations=off to boot configuration\n'
    printf '[ 5] CU / WGP + UMR       — Compute-unit tools and diagnostics\n'
    printf '[ R] Refresh               — Re-check current state\n'
    printf '[ 0] Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in 1) ui_require_root extras swap enable 16G; ui_pause;; 2) ui_require_root extras zswap enable; ui_pause;; 3) ui_require_root extras rdseed hide; ui_pause;; 4) ui_require_root extras mitigations off; ui_pause;; 5) ui_require_root cu status; ui_pause;; r) ;; 0) return;; esac
  done
}
