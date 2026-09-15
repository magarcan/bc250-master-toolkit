#!/usr/bin/env bash

bc250_memory_status() {
  local total avail card path vram_used vram_total gtt_total
  total=$(awk '/MemTotal:/{printf "%d",$2/1024}' /proc/meminfo)
  avail=$(awk '/MemAvailable:/{printf "%d",$2/1024}' /proc/meminfo)
  card=$(bc250_gpu_card 2>/dev/null || true)

  printf 'Memory / UMA\n\n'
  printf '  System RAM (kernel-visible)  %s MiB (%.1f GiB)\n' "$total" "$(awk -v m="$total" 'BEGIN {printf "%.1f",m/1024}')"
  printf '  RAM currently available      %s MiB (%.1f GiB)\n' "$avail" "$(awk -v m="$avail" 'BEGIN {printf "%.1f",m/1024}')"

  if [ -n "$card" ]; then
    path=$(bc250_card_path "$card" 2>/dev/null || true)
    if [ -r "$path/device/mem_info_vram_total" ]; then
      vram_total=$(awk '{printf "%d",$1/1048576}' "$path/device/mem_info_vram_total")
    else
      vram_total='N/A'
    fi
    if [ -r "$path/device/mem_info_vram_used" ]; then
      vram_used=$(awk '{printf "%d",$1/1048576}' "$path/device/mem_info_vram_used")
    else
      vram_used='N/A'
    fi
    printf '  UMA / VRAM reservation       %s MiB' "$vram_total"
    [ "$vram_total" != 'N/A' ] && printf ' (%.1f GiB)' "$(awk -v m="$vram_total" 'BEGIN {printf "%.1f",m/1024}')"
    printf '\n'
    printf '  UMA / VRAM currently used    %s MiB\n' "$vram_used"

    if [ -r "$path/device/mem_info_gtt_total" ]; then
      gtt_total=$(awk '{printf "%d",$1/1048576}' "$path/device/mem_info_gtt_total")
      printf '  GPU dynamic system memory    %s MiB (GTT)\n' "$gtt_total"
    else
      printf '  GPU dynamic system memory    not exposed by driver\n'
    fi
  else
    warn 'BC-250 GPU not detected; VRAM/UMA telemetry unavailable.'
  fi

  printf '\nInterpretation\n'
  if [ "$vram_total" = '512' ]; then
    printf '  512 MiB is the current UMA minimum/reservation reported by amdgpu.\n'
    printf '  It does not mean the BC-250 is limited to 512 MiB of usable GPU memory.\n'
    printf '  With the dynamic UMA configuration, additional system memory can be\n'
    printf '  used by the GPU through GTT as required.\n'
  else
    printf '  The values above are the live kernel-visible memory allocation.\n'
  fi

  printf '\nRecommended profiles\n'
  printf '  512 MiB dynamic  — General desktop / gaming baseline\n'
  printf '  4 GiB fixed      — GPU-heavy workloads with more predictable VRAM\n'
  printf '  6–8 GiB fixed    — Large GPU workloads; leaves less RAM to the CPU\n'
}

bc250_memory_recommendations() {
  cat <<'EOF'
  4 GB VRAM / 12 GB RAM  — CPU-heavy workloads
  8 GB VRAM / 8 GB RAM   — balanced / general-purpose baseline
  12 GB VRAM / 4 GB RAM  — GPU-heavy workloads
  16 GB VRAM / minimal RAM — specialized GPU workloads only
EOF
}
