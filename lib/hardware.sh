#!/usr/bin/env bash
bc250_gpu_card() {
  local card vendor device
  for card in /sys/class/drm/card*; do
    [ -r "$card/device/vendor" ] || continue
    vendor=$(cat "$card/device/vendor" 2>/dev/null); device=$(cat "$card/device/device" 2>/dev/null)
    if [ "$vendor" = "0x1002" ] && [ "$device" = "0x13fe" ]; then basename "$card"; return 0; fi
  done
  return 1
}
bc250_hwmon() {
  local card="$1" h
  for h in "$card"/device/hwmon/hwmon*; do [ -d "$h" ] && { echo "$h"; return; }; done
  return 1
}
bc250_gpu_temp() { local h="$1" f; for f in "$h"/temp1_input "$h"/temp2_input; do [ -r "$f" ] && { awk '{printf "%.1f",$1/1000}' "$f"; return; }; done; echo N/A; }
bc250_cpu_temp() {
  local h f n
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue; n=$(cat "$h/name")
    case "$n" in k10temp|zenpower*) for f in "$h"/temp*_input; do [ -r "$f" ] && { awk '{printf "%.1f",$1/1000}' "$f"; return; }; done;; esac
  done
  echo N/A
}
bc250_gpu_mclk() { local h="$1" f; for f in "$h"/freq2_input "$h"/freq3_input; do [ -r "$f" ] && { awk '{printf "%d",$1/1000000}' "$f"; return; }; done; echo N/A; }
bc250_gpu_sclk() { local h="$1" f="$1/freq1_input"; [ -r "$f" ] && { awk '{printf "%d",$1/1000000}' "$f"; return; }; echo N/A; }
bc250_gpu_busy() { local card="$1"; [ -r "$card/device/gpu_busy_percent" ] && cat "$card/device/gpu_busy_percent" || echo N/A; }
bc250_gpu_vram() {
  local card="$1" used total
  if [ -r "$card/device/mem_info_vram_used" ] && [ -r "$card/device/mem_info_vram_total" ]; then
    used=$(awk '{printf "%d",$1/1048576}' "$card/device/mem_info_vram_used")
    total=$(awk '{printf "%d",$1/1048576}' "$card/device/mem_info_vram_total")
    echo "$used $total"
  else echo "N/A N/A"; fi
}
bc250_bios() { [ -r /sys/class/dmi/id/bios_version ] && cat /sys/class/dmi/id/bios_version || echo N/A; }
bc250_kernel_ok() { uname -r | grep -qi bc250; }
bc250_bios_ok() { [ "$(bc250_bios)" = P3.00 ]; }
bc250_governor_ok() { systemctl is-active --quiet cyan-skillfish-governor-smu.service; }
bc250_telemetry_ok() { local c; c=$(bc250_gpu_card) || return 1; [ -r "$c/device/gpu_busy_percent" ] && bc250_hwmon "$c" >/dev/null 2>&1; }
