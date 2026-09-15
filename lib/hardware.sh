#!/usr/bin/env bash

bc250_gpu_card() {
  local card vendor device
  for card in /sys/class/drm/card*; do
    [ -r "$card/device/vendor" ] || continue
    vendor=$(cat "$card/device/vendor" 2>/dev/null)
    device=$(cat "$card/device/device" 2>/dev/null)
    if [ "$vendor" = "0x1002" ] && [ "$device" = "0x13fe" ]; then
      basename "$card"
      return 0
    fi
  done
  return 1
}

bc250_card_path() {
  case "$1" in
    /sys/class/drm/*) printf '%s\n' "$1" ;;
    card*) printf '/sys/class/drm/%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

bc250_hwmon() {
  local card="$1" base h
  base=$(bc250_card_path "$card") || return 1
  for h in "$base"/device/hwmon/hwmon*; do
    [ -d "$h" ] && { echo "$h"; return 0; }
  done
  return 1
}

bc250_gpu_temp() {
  local h="$1" f
  for f in "$h"/temp1_input "$h"/temp2_input; do
    [ -r "$f" ] && { awk '{printf "%.1f",$1/1000}' "$f"; return; }
  done
  echo N/A
}

bc250_cpu_temp() {
  local h f n
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    n=$(cat "$h/name")
    case "$n" in
      k10temp|zenpower*)
        for f in "$h"/temp*_input; do
          [ -r "$f" ] && { awk '{printf "%.1f",$1/1000}' "$f"; return; }
        done
      ;;
    esac
  done
  echo N/A
}

bc250_vrm_temp() {
  local h name f
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    name=$(cat "$h/name" 2>/dev/null)
    case "$name" in
      nct6686|nct6687|nct6683)
        f="$h/temp3_input"
        [ -r "$f" ] && { awk '{printf "%.1f",$1/1000}' "$f"; return; }
      ;;
    esac
  done
  echo N/A
}

bc250_gpu_mclk() {
  local h="$1" f
  for f in "$h"/freq2_input "$h"/freq3_input; do
    [ -r "$f" ] && { awk '{printf "%d",$1/1000000}' "$f"; return; }
  done
  echo N/A
}

bc250_gpu_sclk() {
  local h="$1" f="$1/freq1_input"
  [ -r "$f" ] && { awk '{printf "%d",$1/1000000}' "$f"; return; }
  echo N/A
}

bc250_gpu_busy() {
  local card="$1" path
  path=$(bc250_card_path "$card") || { echo N/A; return; }
  [ -r "$path/device/gpu_busy_percent" ] && cat "$path/device/gpu_busy_percent" || echo N/A
}

bc250_gpu_vram() {
  local card="$1" path used total
  path=$(bc250_card_path "$card") || { echo "N/A N/A"; return; }
  if [ -r "$path/device/mem_info_vram_used" ] && [ -r "$path/device/mem_info_vram_total" ]; then
    used=$(awk '{printf "%d",$1/1048576}' "$path/device/mem_info_vram_used")
    total=$(awk '{printf "%d",$1/1048576}' "$path/device/mem_info_vram_total")
    echo "$used $total"
  else
    echo "N/A N/A"
  fi
}

bc250_gpu_dpm_range() {
  local card="$1" path="$2" min max line freq
  [ -n "$path" ] || path=$(bc250_card_path "$card") || { echo "N/A N/A"; return; }
  [ -r "$path/device/pp_dpm_sclk" ] || { echo "N/A N/A"; return; }
  min=; max=
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*[0-9]+:[[:space:]]*([0-9]+)[[:space:]]*[Mm][Hh][Zz] ]] || continue
    freq="${BASH_REMATCH[1]}"
    [ -z "$min" ] && min="$freq"
    max="$freq"
  done < "$path/device/pp_dpm_sclk"
  [ -n "$min" ] && [ -n "$max" ] && printf '%s %s\n' "$min" "$max" || printf 'N/A N/A\n'
}

bc250_cpu_cores() {
  lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l
}

bc250_cpu_threads() {
  nproc
}

bc250_cpu_driver() {
  cat /sys/devices/system/cpu/cpufreq/policy0/scaling_driver 2>/dev/null || echo N/A
}

bc250_cpu_governor() {
  cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null || echo N/A
}

bc250_cpu_freq() {
  local f=/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq
  [ -r "$f" ] && awk '{printf "%d",$1/1000}' "$f" || echo N/A
}

# CPU Diagnostics backend used by Hardware & Telemetry.
# Keep this function dependency-light: all values come from existing
# hardware helpers and standard cpufreq sysfs interfaces.
bc250_cpu_status() {
  local policy=/sys/devices/system/cpu/cpufreq/policy0
  local cores threads driver governor freq temp min max boost governors

  printf 'CPU Diagnostics\n\n'

  cores=$(bc250_cpu_cores)
  threads=$(bc250_cpu_threads)
  driver=$(bc250_cpu_driver)
  governor=$(bc250_cpu_governor)
  freq=$(bc250_cpu_freq)
  temp=$(bc250_cpu_temp)

  printf '  Topology              %sC / %sT\n' "$cores" "$threads"
  printf '  Scaling driver        %s\n' "$driver"
  printf '  Governor              %s\n' "$governor"
  printf '  Current frequency     %s MHz\n' "$freq"
  printf '  Temperature           %s°C\n' "$temp"

  if [ -r "$policy/cpuinfo_min_freq" ]; then
    min=$(awk '{printf "%d",$1/1000}' "$policy/cpuinfo_min_freq")
    printf '  Hardware min          %s MHz\n' "$min"
  else
    printf '  Hardware min          N/A\n'
  fi

  if [ -r "$policy/cpuinfo_max_freq" ]; then
    max=$(awk '{printf "%d",$1/1000}' "$policy/cpuinfo_max_freq")
    printf '  Hardware max          %s MHz\n' "$max"
  else
    printf '  Hardware max          N/A\n'
  fi

  if [ -r "$policy/boost" ]; then
    boost=$(cat "$policy/boost" 2>/dev/null || true)
    case "$boost" in
      1) printf '  CPU boost              enabled\n' ;;
      0) printf '  CPU boost              disabled\n' ;;
      *) printf '  CPU boost              %s\n' "${boost:-N/A}" ;;
    esac
  else
    printf '  CPU boost              N/A\n'
  fi

  if [ -r "$policy/scaling_available_governors" ]; then
    governors=$(cat "$policy/scaling_available_governors" 2>/dev/null || true)
    printf '  Available governors    %s\n' "${governors:-N/A}"
  else
    printf '  Available governors    N/A\n'
  fi

  printf '\nInterpretation\n'
  if [ "$cores" -ge 8 ] && [ "$threads" -ge 16 ]; then
    printf '  CPU topology is consistent with an unlocked 8C / 16T BC-250.\n'
  else
    printf '  CPU topology is below the expected 8C / 16T BC-250 configuration.\n'
    printf '  Check the BIOS CPU Core Unlock setting before applying CPU tuning.\n'
  fi
}

bc250_bios() {
  [ -r /sys/class/dmi/id/bios_version ] && cat /sys/class/dmi/id/bios_version || echo N/A
}

bc250_kernel_ok() { uname -r | grep -qi bc250; }
bc250_bios_ok() { [ "$(bc250_bios)" = P3.00 ]; }
bc250_governor_ok() { systemctl is-active --quiet cyan-skillfish-governor-smu.service; }

bc250_telemetry_ok() {
  local c p
  c=$(bc250_gpu_card) || return 1
  p=$(bc250_card_path "$c") || return 1
  [ -r "$p/device/gpu_busy_percent" ] && bc250_hwmon "$c" >/dev/null 2>&1
}
