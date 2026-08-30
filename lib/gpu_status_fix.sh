#!/usr/bin/env bash

# Read-only status must work before any OC operation has published state.
bc250_gpu_oc_status() {
  local profile range min max freq volt card dpm
  profile=$(bc250_gpu_oc_active_profile 2>/dev/null || echo none)
  range=$(bc250_gpu_oc_range 2>/dev/null || true)
  if [ -r "$GPU_OC_PUBLIC_STATE" ]; then
    freq=$(sed -n 's/^GPU_OC_MAX_MHZ=//p' "$GPU_OC_PUBLIC_STATE")
    volt=$(sed -n 's/^GPU_OC_VOLTAGE_MV=//p' "$GPU_OC_PUBLIC_STATE")
  elif [[ "$profile" =~ ^manual-([0-9]+)mhz-([0-9]+)mv$ ]]; then
    freq="${BASH_REMATCH[1]}"; volt="${BASH_REMATCH[2]}"
  else
    freq=$(bc250_gpu_oc_profile_value "$profile" frequency_mhz 2>/dev/null || true)
    volt=$(bc250_gpu_oc_profile_value "$profile" voltage_mv 2>/dev/null || true)
  fi
  printf 'GPU OC/UV control\n  Active profile        : %s\n' "$profile"
  if [ -n "$range" ]; then
    min=${range%%|*}; max=${range#*|}
    card=$(bc250_gpu_card 2>/dev/null || true)
    dpm=$(bc250_gpu_dpm_range "$card" "$(bc250_card_path "$card")" 2>/dev/null || true)
    if [[ "$dpm" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
      printf '  DPM hardware          : %s–%s MHz\n' "${dpm% *}" "${dpm#* }"
    else
      printf '  DPM hardware          : N/A\n'
    fi
    printf '  Governor range        : %s–%s MHz\n' "$min" "$max"
  else
    printf '  Governor range        : N/A\n'
  fi
  [ -n "$freq" ] && [ -n "$volt" ] && printf '  Target                : %s MHz @ %s mV\n' "$freq" "$volt"
  printf '  Config                : %s\n' "$GPU_OC_CONFIG"
  if [ -n "$range" ]; then
    info 'Read-only: range comes directly from the active Cyan-Skillfish configuration.'
  else
    warn 'Cyan-Skillfish frequency-range configuration is unavailable.'
  fi
}
