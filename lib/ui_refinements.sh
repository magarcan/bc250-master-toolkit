#!/usr/bin/env bash

# Small presentation refinements kept separate from the canonical UI while
# the interface is being iterated. These functions intentionally override
# the corresponding UI views without touching backend/telemetry code.

ui_cpu_load_percent() {
  local a b
  read -r _ a _ _ _ _ _ _ _ _ < /proc/stat 2>/dev/null || return 0
  sleep 0.20
  read -r _ b _ _ _ _ _ _ _ _ < /proc/stat 2>/dev/null || return 0
  local d=$((b-a))
  [ "$d" -gt 0 ] && printf '%d' $((100 - (100 * (b-a)) / d)) || printf '0'
}

ui_live_snapshot() {
  ui_banner
  printf 'Live System Snapshot\n\n'
  local card h vr load
  card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" != card* ]]; then
    warn 'BC-250 GPU not detected.'
    return 1
  fi
  h=$(bc250_hwmon "$card" 2>/dev/null || true)
  vr=$(bc250_gpu_vram "$card")
  load=$(awk '/^cpu / {idle=$5; total=$2+$3+$4+$5+$6+$7+$8; print total,idle; exit}' /proc/stat)
  sleep 0.20
  local total2 idle2 t1 i1 cpu_load=0
  read -r t1 i1 <<< "$load"
  read -r _ total2 idle2 <<< "$(awk '/^cpu / {print "cpu",$2+$3+$4+$5+$6+$7+$8,$5; exit}' /proc/stat)"
  if [ "$total2" -gt "$t1" ]; then
    cpu_load=$((100 * ((total2-t1)-(idle2-i1)) / (total2-t1)))
  fi
  printf 'CPU\n──────────────────────────────────────────────────────────────\n'
  printf '  Load                   %s%%\n' "$cpu_load"
  printf '  Frequency              %s MHz\n' "$(bc250_cpu_freq)"
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
