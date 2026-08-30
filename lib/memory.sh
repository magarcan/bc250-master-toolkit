#!/usr/bin/env bash
bc250_memory_status() {
  local total avail card vram
  total=$(awk '/MemTotal:/{printf "%d",$2/1024}' /proc/meminfo)
  avail=$(awk '/MemAvailable:/{printf "%d",$2/1024}' /proc/meminfo)
  card=$(bc250_gpu_card) || card=""
  if [ -n "$card" ]; then vram=$(bc250_gpu_vram "$card"); else vram="N/A N/A"; fi
  echo "$total $avail $vram"
}
bc250_memory_recommendations() {
  cat <<'EOF'
  4 GB VRAM / 12 GB RAM  — CPU-heavy workloads
  8 GB VRAM / 8 GB RAM   — balanced / general-purpose baseline
  12 GB VRAM / 4 GB RAM  — GPU-heavy workloads
  16 GB VRAM / minimal RAM — specialized GPU workloads only
EOF
}
