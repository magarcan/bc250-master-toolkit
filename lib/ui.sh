#!/usr/bin/env bash

# Canonical UI primitives.
ok()      { printf '  [ OK ] %s\n' "$*"; }
warn()    { printf '  [WARN] %s\n' "$*"; }
info()    { printf '  [INFO] %s\n' "$*"; }
heading() { printf '\n%s\n──────────────────────────────────────────────────────────────\n' "$*"; }
die()     { printf '  [ERR ] %s\n' "$*" >&2; return 1; }

ui_pause() { printf '\n'; read -r -p 'Press Enter to continue...' _; }
ui_banner() {
  printf '\n╔══════════════════════════════════════════════════════════════════╗\n'
  printf '║                   CachyOS BC250 Master Toolkit                  ║\n'
  printf '║               Platform • Performance • Diagnostics              ║\n'
  printf '║                             v%s                             ║\n' "$VERSION"
  printf '╚══════════════════════════════════════════════════════════════════╝\n\n'
}

ui_status() {
  ui_banner
  printf 'System Status\n\n'
  printf '  BIOS                   %s\n' "$(bc250_bios)"
  printf '  Kernel                 %s\n' "$(uname -r)"
  printf '  CPU                    %sC / %sT\n' "$(bc250_cpu_cores)" "$(bc250_cpu_threads)"
  printf '  CPU driver             %s\n' "$(bc250_cpu_driver)"
  printf '  CPU governor           %s\n' "$(bc250_cpu_governor)"
  local card; card=$(bc250_gpu_card 2>/dev/null || true)
  printf '  GPU                    %s\n' "${card:-not detected}"
}

ui_preflight_install_menu() {
  local missing=() choice
  bc250_bios_ok || missing+=("BIOS P3.00")
  bc250_kernel_ok || missing+=("CachyOS BC-250 kernel")
  [ -x /usr/bin/cyan-skillfish-governor-smu ] || missing+=("Cyan-Skillfish governor")
  [ -f /etc/cyan-skillfish-governor-smu/config.toml ] || missing+=("Cyan-Skillfish configuration")
  bc250_governor_ok || missing+=("Cyan-Skillfish service")
  [ -x /usr/local/bin/bc250-cu-live-manager ] || missing+=("CU/WGP manager")
  bc250_umr_present || missing+=("UMR")

  if [ "${#missing[@]}" -eq 0 ]; then
    ok 'All actionable preflight requirements are present.'
    return 0
  fi

  heading 'Missing / actionable components'
  local item
  for item in "${missing[@]}"; do warn "$item"; done
  printf '\n[ 1]  BIOS Setup           Review/open P3.00 firmware project\n'
  printf '[ 2]  Kernel Setup         Install linux-cachyos-bc250 if needed\n'
  printf '[ 3]  CU / WGP Setup       Install UMR + CU/WGP manager\n'
  printf '[ 4]  GPU Governor Status  Review governor state\n'
  printf '[ 5]  Re-run Preflight     Check again after changes\n'
  printf '[ 0]  Back\n\nEnter selection: '
  read -r choice
  case "${choice,,}" in
    1) bc250_bios_setup_menu_action;;
    2) bc250_kernel_setup_menu_action;;
    3) bc250_cu_setup_menu_action;;
    4) ui_gpu_status; ui_pause;;
    5) ui_preflight;;
    0) return;;
  esac
}

ui_preflight() {
  ui_banner
  printf 'Preflight / Platform Validation\n\n'
  local card; card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" != card* ]]; then
    warn 'AMD BC-250 GPU was not detected.'
    return 1
  fi

  ok 'AMD BC-250 detected (PCI 1002:13fe).'
  printf '\n  OS              : %s\n  Kernel          : %s\n  BIOS            : %s\n  CPU             : %sC / %sT\n  CPU driver      : %s\n  CPU governor    : %s\n  GPU             : %s\n\n' "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")" "$(uname -r)" "$(bc250_bios)" "$(bc250_cpu_cores)" "$(bc250_cpu_threads)" "$(bc250_cpu_driver)" "$(bc250_cpu_governor)" "$card"

  local missing=()
  bc250_bios_ok && ok 'BIOS P3.00 detected — BC-250 telemetry profile.' || { warn "BIOS $(bc250_bios) — P3.00 recommended."; missing+=("BIOS P3.00"); }
  bc250_kernel_ok && ok 'CachyOS BC-250 kernel detected.' || { warn "Kernel $(uname -r) — BC-250 kernel recommended."; missing+=("CachyOS BC-250 kernel"); }
  command -v cpupower >/dev/null 2>&1 && ok 'cpupower available' || { warn 'cpupower missing'; missing+=("cpupower"); }
  command -v vulkaninfo >/dev/null 2>&1 && ok 'vulkaninfo available' || { warn 'vulkaninfo missing'; missing+=("vulkaninfo"); }
  [ -x /usr/bin/cyan-skillfish-governor-smu ] && ok 'Cyan-Skillfish binary installed' || { warn 'Cyan-Skillfish binary missing'; missing+=("Cyan-Skillfish governor"); }
  [ -f /etc/cyan-skillfish-governor-smu/config.toml ] && ok 'Cyan-Skillfish configuration present' || { warn 'Cyan-Skillfish configuration missing'; missing+=("Cyan-Skillfish configuration"); }
  bc250_governor_ok && ok 'GPU governor service active' || { warn 'GPU governor service inactive'; missing+=("Cyan-Skillfish service"); }
  bc250_telemetry_ok && ok 'GPU telemetry interfaces available' || { warn 'GPU telemetry interfaces incomplete'; missing+=("GPU telemetry"); }
  [ -r "/sys/class/drm/$card/device/pp_dpm_sclk" ] && ok 'GPU DPM interface available' || { warn 'GPU DPM interface unavailable'; missing+=("GPU DPM"); }
  [ -r "/sys/class/drm/$card/device/mem_info_vram_total" ] && ok 'VRAM telemetry available' || { warn 'VRAM telemetry unavailable'; missing+=("VRAM telemetry"); }
  [ -x /usr/local/bin/bc250-cu-live-manager ] && ok 'CU/WGP manager installed' || { warn 'CU/WGP manager missing'; missing+=("CU/WGP manager"); }
  bc250_umr_present && ok 'UMR available' || { warn 'UMR missing'; missing+=("UMR"); }

  if [ "${#missing[@]}" -eq 0 ]; then
    printf '\n  [ OK ] Platform validation: PASS\n'
    printf '        All required components are installed and operational.\n'
    return 0
  fi

  printf '\n  [WARN] Platform validation: INCOMPLETE\n'
  printf '        %s component(s) require attention.\n' "${#missing[@]}"
  printf '\nConfigure missing components now? [Y/n]: '
  local answer
  read -r answer
  case "${answer,,}" in
    n) info 'No setup changes requested.';;
    *) ui_preflight_install_menu;;
  esac
}

ui_gpu_status() {
  ui_banner
  printf 'GPU Status\n\n'
  systemctl is-active --quiet "$CYAN_SERVICE" 2>/dev/null && printf 'Governor service       : active\n' || printf 'Governor service       : inactive\n'
  local card h vr; card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" == card* ]]; then
    h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card")
    printf 'GPU                    : %s\nGPU SCLK               : %s MHz\nGPU busy               : %s%%\nGPU temp               : %s°C\nVRAM                   : %s/%s MB\nVRAM MCLK              : %s MHz\nCPU temp               : %s°C\nVRM temp               : %s°C\n' "$card" "$(bc250_gpu_sclk "$h")" "$(bc250_gpu_busy "$card")" "$(bc250_gpu_temp "$h")" "${vr% *}" "${vr#* }" "$(bc250_gpu_mclk "$h")" "$(bc250_cpu_temp)" "$(bc250_vrm_temp)"
  else
    warn 'BC-250 GPU not detected.'
    return 1
  fi
  printf '\nGovernor / OC-UV\n──────────────────────────────────────────────────────────────\n'
  bc250_gpu_oc_status 2>/dev/null || true
}

ui_live_snapshot() {
  ui_banner
  printf 'Live System Snapshot\n\n'
  local card h vr
  card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" != card* ]]; then
    warn 'BC-250 GPU not detected.'
    return 1
  fi
  h=$(bc250_hwmon "$card" 2>/dev/null || true)
  vr=$(bc250_gpu_vram "$card")
  printf 'CPU\n──────────────────────────────────────────────────────────────\n'
  printf '  Load / frequency      %s MHz\n' "$(bc250_cpu_freq)"
  printf '  Temperature            %s°C\n' "$(bc250_cpu_temp)"
  printf '  Cores / threads        %sC / %sT\n' "$(bc250_cpu_cores)" "$(bc250_cpu_threads)"
  printf '\nGPU\n──────────────────────────────────────────────────────────────\n'
  printf '  Device                 %s\n' "$card"
  printf '  SCLK                   %s MHz\n' "$(bc250_gpu_sclk "$h")"
  printf '  Busy                   %s%%\n' "$(bc250_gpu_busy "$card")"
  printf '  Temperature            %s°C\n' "$(bc250_gpu_temp "$h")"
  printf '  VRAM                   %s/%s MB\n' "${vr% *}" "${vr#* }"
  printf '  MCLK                   %s MHz\n' "$(bc250_gpu_mclk "$h")"
  printf '\nVRM\n──────────────────────────────────────────────────────────────\n'
  printf '  Temperature            %s°C\n' "$(bc250_vrm_temp)"
}

ui_require_root() {
  if [ "$EUID" -eq 0 ]; then
    case "$1 $2 $3" in
      gpu\ oc\ apply) bc250_gpu_oc_apply "${4:-}";;
      gpu\ oc\ manual) bc250_gpu_oc_manual "${4:-}" "${5:-}" "${6:-}";;
      gpu\ oc\ reset) bc250_gpu_oc_reset;;
      extras\ swap\ enable) bc250_swap_enable "${4:-16G}";;
      extras\ zswap\ enable) bc250_zswap_enable;;
      extras\ rdseed\ hide) bc250_rdseed_hide;;
      extras\ mitigations\ off) bc250_set_cmdline_flag mitigations=off && bc250_update_boot;;
      cu\ install) bc250_cu_install;;
      cu\ umr\ install) bc250_umr_install;;
      cu\ status) bc250_cu_status;;
      *) die "Unsupported privileged action: $*"; return 1;;
    esac
    return $?
  fi
  command -v sudo >/dev/null 2>&1 || { die 'sudo is required for this operation.'; return 1; }
  sudo -v || { die 'Authorization was cancelled.'; return 1; }
  sudo env BC250_PRIVILEGED=1 "$ROOT/bc250-master-toolkit" "$@"
}

ui_gpu_profiles() {
  while true; do
    ui_banner
    printf 'Performance Lab — GPU\n\n'
    printf 'GPU\n──────────────────────────────────────────────────────────────\n'
    printf '[ 1]  GPU Status            Telemetry + governor + OC/UV state\n'
    printf '[ 2]  Stock                 1850 MHz @ 930 mV\n'
    printf '[ 3]  Balanced              2000 MHz @ 1000 mV\n'
    printf '[ 4]  Aggressive            2100 MHz @ 1025 mV  [EXPERIMENTAL]\n'
    printf '[ 5]  Maximum Experimental  2200 MHz @ 1050 mV  [EXPERIMENTAL]\n'
    printf '[ C]  Custom                Enter MHz / mV / minimum MHz\n'
    printf '[ R]  Reset                 Restore saved GPU configuration\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_gpu_status; ui_pause;;
      2) ui_require_root gpu oc apply stock; ui_pause;;
      3) ui_require_root gpu oc apply balanced; ui_pause;;
      4) ui_require_root gpu oc apply aggressive; ui_pause;;
      5) ui_require_root gpu oc apply maximum-experimental; ui_pause;;
      c) read -r -p 'Maximum GPU frequency MHz: ' f; read -r -p 'Voltage mV: ' v; read -r -p 'Minimum GPU frequency MHz [600]: ' m; ui_require_root gpu oc manual "$f" "$v" "${m:-600}"; ui_pause;;
      r) ui_require_root gpu oc reset; ui_pause;;
      0) return;;
    esac
  done
}

ui_performance() {
  while true; do
    ui_banner
    printf 'Performance Lab\n\n'
    printf '[ 1]  GPU Performance      GPU status, profiles and OC/UV\n'
    printf '[ 2]  CPU Performance      Reserved for validated CPU tuning\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_gpu_profiles;;
      2) ui_banner; printf 'CPU Performance\n\n'; info 'CPU tuning remains in the validation/research phase. No settings are changed here yet.'; ui_pause;;
      0) return;;
    esac
  done
}

ui_platform() {
  while true; do
    ui_banner
    printf 'Platform Setup\n\n'
    printf '[ 1]  BIOS                Check recommended P3.00 firmware\n'
    printf '[ 2]  CachyOS Kernel      Install/activate linux-cachyos-bc250\n'
    printf '[ 3]  GPU Governor        Verify Cyan-Skillfish SMU governor\n'
    printf '[ 4]  CU / WGP            Install/update CU/WGP manager (UMR)\n'
    printf '[ 5]  Preflight            Full validation + assisted setup\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) bc250_bios_setup_menu_action;;
      2) bc250_kernel_setup_menu_action;;
      3) ui_gpu_status; ui_pause;;
      4) bc250_cu_setup_menu_action;;
      5) ui_preflight; ui_pause;;
      0) return;;
    esac
  done
}

ui_hardware() {
  while true; do
    ui_banner
    printf 'Hardware & Telemetry\n\n'
    printf '[ 1]  Live System Snapshot  CPU / GPU / VRM / VRAM telemetry\n'
    printf '[ 2]  Memory / UMA          Current RAM/VRAM split and recommendations\n'
    printf '[ 3]  CU / WGP              Compute-unit state and diagnostics\n'
    printf '[ 4]  CPU Diagnostics       CPU topology, driver and governor\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_live_snapshot; ui_pause;;
      2) ui_banner; printf 'Memory / UMA\n\n'; bc250_memory_status; echo; bc250_memory_recommendations; ui_pause;;
      3) ui_require_root cu status; ui_pause;;
      4) ui_banner; printf 'CPU Diagnostics\n\n'; printf '  Cores                  %s\n  Threads                %s\n  Driver                 %s\n  Governor               %s\n  Current frequency      %s MHz\n  CPU temperature        %s°C\n  VRM temperature        %s°C\n' "$(bc250_cpu_cores)" "$(bc250_cpu_threads)" "$(bc250_cpu_driver)" "$(bc250_cpu_governor)" "$(bc250_cpu_freq)" "$(bc250_cpu_temp)" "$(bc250_vrm_temp)"; ui_pause;;
      0) return;;
    esac
  done
}

ui_extras_status() {
  ui_banner
  printf 'System Extras\n\n'
  heading 'Current state'
  bc250_extras_status
  local conf
  conf=$(bc250_boot_conf 2>/dev/null || true)
  printf '\n  Boot configuration     %s\n' "${conf:-not found}"
  if [ -n "$conf" ]; then
    grep -q 'loglevel=0' "$conf" 2>/dev/null && ok 'RDSEED warning hidden' || info 'RDSEED warning: default'
    grep -q 'mitigations=off' "$conf" 2>/dev/null && warn 'CPU mitigations disabled' || info 'CPU mitigations: default'
  fi
}

ui_extras() {
  while true; do
    ui_extras_status
    printf '\n'
    heading 'Available actions'
    printf '[ 1]  Enable Swap          Configure swap\n'
    printf '[ 2]  ZRAM → ZSWAP        Enable ZSWAP and disable systemd zram\n'
    printf '[ 3]  Hide RDSEED Warning  Set boot loglevel=0\n'
    printf '[ 4]  Disable Mitigations  Add mitigations=off to boot configuration\n'
    printf '[ 5]  CU / WGP + UMR       Compute-unit tools and diagnostics\n'
    printf '[ R]  Refresh               Re-check current state\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_require_root extras swap enable 16G; ui_pause;;
      2) ui_require_root extras zswap enable; ui_pause;;
      3) ui_require_root extras rdseed hide; ui_pause;;
      4) ui_require_root extras mitigations off; ui_pause;;
      5) ui_require_root cu status; ui_pause;;
      r) ;;
      0) return;;
    esac
  done
}

ui_recovery() {
  while true; do
    ui_banner
    printf 'Recovery & Revert\n\n'
    printf '[ 1]  Reset GPU OC/UV      Restore saved GPU configuration\n'
    printf '[ 2]  Restore boot config  Restore toolkit backup when available\n'
    printf '[ 3]  Show system status   Diagnose before reverting\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_require_root gpu oc reset; ui_pause;;
      2) ui_require_root bash -c 'if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot backup found."; fi'; ui_pause;;
      3) ui_status; ui_pause;;
      0) return;;
    esac
  done
}

ui_menu() {
  while true; do
    ui_banner
    printf 'Validation\n──────────────────────────────────────────────────────────────\n'
    printf '[ P]  Preflight             Validate and help configure missing components\n\n'
    printf 'Platform\n──────────────────────────────────────────────────────────────\n'
    printf '[ 1]  Platform Setup        BIOS / kernel / governor / CU-WGP\n'
    printf '[ 2]  Performance Lab       GPU status, profiles and CPU tuning\n'
    printf '[ 3]  Hardware & Telemetry  Live measurements and diagnostics\n'
    printf '[ 4]  System Extras         Status + optional system changes\n'
    printf '[ 5]  Recovery & Revert     Undo supported changes\n\n'
    printf 'System\n──────────────────────────────────────────────────────────────\n'
    printf '[ S]  Status                Current system summary\n'
    printf '[ U]  Update Toolkit        Update from GitHub checkout\n'
    printf '[ 0]  Exit\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      p) ui_preflight; ui_pause;;
      s) ui_status; ui_pause;;
      1) ui_platform;;
      2) ui_performance;;
      3) ui_hardware;;
      4) ui_extras;;
      5) ui_recovery;;
      u) info 'Use git pull in the toolkit checkout to update safely.'; ui_pause;;
      0) return;;
    esac
  done
}

bc250_ui_main() {
  case "${1:-menu}" in
    menu) ui_menu;;
    preflight) ui_preflight;;
    status) ui_status;;
    gpu)
      case "${2:-status}" in
        status) ui_gpu_status;;
        oc)
          case "${3:-status}" in
            profiles) printf 'Stock 1850 MHz @ 930 mV\nBalanced 2000 MHz @ 1000 mV\nAggressive 2100 MHz @ 1025 mV\nMaximum Experimental 2200 MHz @ 1050 mV\n';;
            status) bc250_gpu_oc_status;;
            apply) ui_require_root gpu oc apply "${4:-}";;
            manual) ui_require_root gpu oc manual "${4:-}" "${5:-}" "${6:-}";;
            reset) ui_require_root gpu oc reset;;
            *) die 'Unknown GPU OC command.'; return 1;;
          esac;;
        *) ui_gpu_status;;
      esac;;
    cpu) ui_banner; printf 'CPU: %sC / %sT\nDriver: %s\nGovernor: %s\nFrequency: %s MHz\n' "$(bc250_cpu_cores)" "$(bc250_cpu_threads)" "$(bc250_cpu_driver)" "$(bc250_cpu_governor)" "$(bc250_cpu_freq)";;
    memory) ui_banner; bc250_memory_status; echo; bc250_memory_recommendations;;
    extras)
      case "${2:-status}" in
        status) bc250_extras_status;;
        swap) [ "${3:-}" = enable ] || die 'Use: extras swap enable [size]'; ui_require_root extras swap enable "${4:-16G}";;
        zswap) ui_require_root extras zswap enable;;
        rdseed) ui_require_root extras rdseed hide;;
        mitigations) [ "${3:-}" = off ] || die 'Use: extras mitigations off'; ui_require_root extras mitigations off;;
        *) die 'Unknown extras command.'; return 1;;
      esac;;
    cu)
      case "${2:-status}" in
        install) ui_require_root cu install;;
        umr) ui_require_root cu umr install;;
        status) bc250_cu_status;;
        *) die 'Unknown CU command.'; return 1;;
      esac;;
    help|-h|--help) printf 'CachyOS BC250 Master Toolkit v%s\n' "$VERSION";;
    *) die "Unknown command: $1"; return 1;;
  esac
}
