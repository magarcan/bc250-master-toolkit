#!/usr/bin/env bash

bc250_clear() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; }

bc250_main_menu() {
  while true; do
    bc250_clear
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              CachyOS BC250 Toolkit                           ║
║           System Setup & Configuration                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

Performance
──────────────────────────────────────────────────────────────
[ 1]  Performance Profiles   CPU & GPU performance profiles

Setup
──────────────────────────────────────────────────────────────
[ 2]  Initial Setup           System configuration tasks
[ 3]  Additional Tools        Additional system utilities
[ 4]  Revert Menu             Undo previously applied settings

System
──────────────────────────────────────────────────────────────
[ S]  Status                  Current system summary
[ U]  Update Toolkit          Download latest version from GitHub
[ 0]  Exit

══════════════════════════════════════════════════════════════
EOF
    read -r -p 'Enter selection: ' sel
    case "${sel,,}" in
      1) bc250_performance_menu;;
      2) bc250_setup_menu;;
      3) bc250_tools_menu;;
      4) bc250_revert_menu;;
      s) status; read -r -p $'\nPress Enter to continue...' _;;
      u) info 'Toolkit self-update will be implemented with the release/update subsystem.'; read -r -p $'\nPress Enter to continue...' _;;
      0) return 0;;
      *) warn 'Invalid selection.'; read -r -p $'\nPress Enter to continue...' _;;
    esac
  done
}

bc250_performance_menu() {
  while true; do
    bc250_clear
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              CachyOS BC250 Toolkit                           ║
║           System Setup & Configuration                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

Performance Profile Menu
──────────────────────────────────────────────────────────────
EOF
    printf 'Active: '
    if [ -r /etc/bc250-master-toolkit/gpu-profile ]; then cat /etc/bc250-master-toolkit/gpu-profile; else printf 'GPU profile not set'; fi
    cat <<'EOF'

Standard Profiles
──────────────────────────────────────────────────────────────
[ 1]  Stock        Conservative GPU baseline
[ 2]  Balanced     GPU 2000 MHz @ 1000 mV
[ 3]  Aggressive   GPU 2100 MHz @ 1025 mV  [EXPERIMENTAL]
[ 4]  Maximum      GPU 2200 MHz @ 1050 mV  [EXPERIMENTAL]

[ G]  GPU profiles
[ C]  CPU profiles  (research phase)
[ M]  Custom        Manual GPU settings
[ 0]  Back to Main Menu

══════════════════════════════════════════════════════════════
EOF
    read -r -p 'Enter selection: ' sel
    case "${sel,,}" in
      1) sudo "$ROOT/bc250-master-toolkit" gpu oc apply stock;;
      2) sudo "$ROOT/bc250-master-toolkit" gpu oc apply balanced;;
      3) sudo "$ROOT/bc250-master-toolkit" gpu oc apply aggressive;;
      4) sudo "$ROOT/bc250-master-toolkit" gpu oc apply maximum-experimental;;
      g) bc250_gpu_oc_profiles; read -r -p $'\nPress Enter to continue...' _;;
      c) info 'CPU OC profiles will be added after the CPU research phase.'; read -r -p $'\nPress Enter to continue...' _;;
      m) read -r -p 'Maximum GPU MHz: ' f; read -r -p 'Voltage mV: ' v; read -r -p 'Minimum MHz [600]: ' m; sudo "$ROOT/bc250-master-toolkit" gpu oc manual "$f" "$v" "${m:-600}";;
      0) return;;
      *) warn 'Invalid selection.'; sleep 1;;
    esac
  done
}

bc250_setup_menu() {
  while true; do
    bc250_clear
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              CachyOS BC250 Toolkit                           ║
║           System Setup & Configuration                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

Initial Setup
──────────────────────────────────────────────────────────────
Run these tasks to configure your BC-250 system.

[ 1]  CachyOS Kernel      Validate BC-250 CachyOS kernel
[ 2]  CPU Governor        CPU governor / future OC subsystem
[ 3]  GPU Governor        Cyan-Skillfish GPU governor service
[ 4]  Enable Swap         Configure system swap
[ 5]  ZRAM -> ZSWAP       Configure ZSWAP
[ 6]  Hide RDSEED Warning Hide boot RDSEED warning
[ 7]  Disable Mitigations Add mitigations=off to Limine
[ A]  Run All (1-7)       Run setup tasks in sequence

⚠  Manual Steps — not included in Run All
──────────────────────────────────────────────────────────────
[ 8]  Compute Units Unlock CU/WGP configuration

[ 0]  Back

══════════════════════════════════════════════════════════════
EOF
    read -r -p 'Enter selection: ' sel
    case "${sel,,}" in
      1) preflight; read -r -p $'\nPress Enter to continue...' _;;
      2) cpu; read -r -p $'\nPress Enter to continue...' _;;
      3) sudo "$ROOT/bc250-master-toolkit" gpu status; read -r -p $'\nPress Enter to continue...' _;;
      4) sudo "$ROOT/bc250-master-toolkit" extras swap enable; read -r -p $'\nPress Enter to continue...' _;;
      5) sudo "$ROOT/bc250-master-toolkit" extras zswap enable; read -r -p $'\nPress Enter to continue...' _;;
      6) sudo "$ROOT/bc250-master-toolkit" extras rdseed hide; read -r -p $'\nPress Enter to continue...' _;;
      7) sudo "$ROOT/bc250-master-toolkit" extras mitigations disable; read -r -p $'\nPress Enter to continue...' _;;
      a) warn 'Run All is intentionally disabled until every task has a validated implementation.'; read -r -p $'\nPress Enter to continue...' _;;
      8) sudo "$ROOT/bc250-master-toolkit" cu status; read -r -p $'\nPress Enter to continue...' _;;
      0) return;;
      *) warn 'Invalid selection.'; sleep 1;;
    esac
  done
}

bc250_tools_menu() { bc250_clear; heading 'Additional Tools'; echo; echo '[ 1] CU/WGP manager'; echo '[ 2] UMR status'; echo '[ 0] Back'; echo; read -r -p 'Enter selection: ' sel; case "${sel:-0}" in 1) sudo "$ROOT/bc250-master-toolkit" cu status;; 2) sudo "$ROOT/bc250-master-toolkit" cu umr status 2>/dev/null || true;; esac; read -r -p $'\nPress Enter to continue...' _; }
bc250_revert_menu() { bc250_clear; heading 'Revert Menu'; echo; echo '[ 1] Reset GPU OC/UV'; echo '[ 0] Back'; echo; read -r -p 'Enter selection: ' sel; case "${sel:-0}" in 1) sudo "$ROOT/bc250-master-toolkit" gpu oc reset;; esac; read -r -p $'\nPress Enter to continue...' _; }
