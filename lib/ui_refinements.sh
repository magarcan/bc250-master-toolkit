#!/usr/bin/env bash

ui_cpu_load_percent() {
  local line1 line2 t1 i1 t2 i2 delta_total delta_idle
  line1=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8,$5; exit}' /proc/stat)
  sleep 0.20
  line2=$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8,$5; exit}' /proc/stat)
  read -r t1 i1 <<< "$line1"
  read -r t2 i2 <<< "$line2"
  delta_total=$((t2-t1)); delta_idle=$((i2-i1))
  if [ "$delta_total" -gt 0 ]; then printf '%d' $((100 * (delta_total-delta_idle) / delta_total)); else printf '0'; fi
}

ui_live_snapshot() {
  ui_banner; printf 'Live System Snapshot\n\n'
  local card h vr load; card=$(bc250_gpu_card 2>/dev/null || true)
  if [[ "$card" != card* ]]; then warn 'BC-250 GPU not detected.'; return 1; fi
  h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card"); load=$(ui_cpu_load_percent)
  heading 'CPU'
  printf '  Load                   %s%%\n  Frequency              %s MHz\n  Temperature            %s°C\n  Cores / threads        %sC / %sT\n' "$load" "$(bc250_cpu_freq)" "$(bc250_cpu_temp)" "$(bc250_cpu_cores)" "$(bc250_cpu_threads)"
  heading 'GPU'
  printf '  Device                 %s\n  SCLK                   %s MHz\n  Busy                   %s%%\n  Temperature            %s°C\n  VRAM                   %s/%s MB\n  MCLK                   %s MHz\n' "$card" "$(bc250_gpu_sclk "$h")" "$(bc250_gpu_busy "$card")" "$(bc250_gpu_temp "$h")" "${vr% *}" "${vr#* }" "$(bc250_gpu_mclk "$h")"
  heading 'VRM'; printf '  Temperature            %s°C\n' "$(bc250_vrm_temp)"
}

ui_extras_status() {
  ui_banner; printf 'System Extras\n\n'; heading 'Current state'
  local swap zswap zram conf rdseed mitigations swapfile
  swap=$(bc250_swap_status 2>/dev/null || true)
  zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N)
  zram=$([ -e /dev/zram0 ] && echo present || echo not-exposed)
  conf=$(bc250_boot_conf 2>/dev/null || true)

  # Distinguish actual swapfile from compressed zram-backed swap.
  swapfile=$(swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {print; exit}')

  printf '  Swapfile              '
  if [ -n "$swapfile" ]; then ok 'Enabled'; printf '                        %s\n' "$swapfile"; else warn 'Not configured'; fi
  printf '  ZRAM                  '
  if [ "$zram" = present ]; then ok 'Active'; else info 'Not exposed'; fi
  printf '  ZSWAP                 '
  if [ "$zswap" = Y ]; then ok 'Enabled'; else warn 'Disabled'; fi
  printf '  Boot configuration    %s\n' "${conf:-not found}"

  rdseed=default; mitigations=default
  if [ -n "$conf" ]; then
    grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed=hidden
    grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations=disabled
  fi
  printf '  RDSEED warning        '; [ "$rdseed" = hidden ] && ok 'Hidden' || info 'Default'
  printf '  CPU mitigations       '; [ "$mitigations" = disabled ] && warn 'Disabled' || info 'Default'
}

ui_extras() {
  while true; do
    ui_extras_status; printf '\n'; heading 'Available actions'
    printf '\n[ 1]  Enable Swap\n      Configure a persistent swapfile (default 16G)\n'
    printf '\n[ 2]  Enable ZSWAP\n      Disable systemd ZRAM and enable compressed swap\n'
    printf '\n[ 3]  Hide RDSEED warning\n      Add loglevel=0 to boot configuration\n'
    printf '\n[ 4]  Disable CPU mitigations\n      Add mitigations=off to boot configuration\n'
    printf '\n[ 5]  CU / WGP + UMR\n      Open compute-unit tools and status\n'
    printf '\n[ R]  Refresh status\n[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_require_root extras swap enable 16G; ui_pause;;
      2) ui_require_root extras zswap enable; ui_pause;;
      3) ui_require_root extras rdseed hide; ui_pause;;
      4) ui_require_root extras mitigations off; ui_pause;;
      5) ui_require_root cu status; ui_pause;;
      r) ;; 0) return;;
    esac
  done
}
