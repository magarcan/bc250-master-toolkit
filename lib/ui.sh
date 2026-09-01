#!/usr/bin/env bash

# Canonical UI primitives.
ok()      { printf '  [ OK ] %s\n' "$*"; }
warn()    { printf '  [WARN] %s\n' "$*"; }
info()    { printf '  [INFO] %s\n' "$*"; }
heading() { printf '\n%s\n──────────────────────────────────────────────────────────────\n' "$*"; }
die()     { printf '  [ERR ] %s\n' "$*" >&2; return 1; }

# Keep status markers colourised consistently across every interactive view.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_RESET=$'\033[0m'
  ok()   { printf '  %s[ OK ]%s %s\n' "$C_OK" "$C_RESET" "$*"; }
  warn() { printf '  %s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*"; }
  info() { printf '  %s[INFO]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
  die()  { printf '  %s[ERR ]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; return 1; }
fi

ui_pause() { printf '\n'; read -r -p 'Press Enter to continue...' _; }
ui_banner() {
  printf '\n╔══════════════════════════════════════════════════════════════════╗\n'
  printf '║                   CachyOS BC250 Master Toolkit                  ║\n'
  printf '║               Platform • Performance • Diagnostics              ║\n'
  printf '║                             v%s                             ║\n' "$VERSION"
  printf '╚══════════════════════════════════════════════════════════════════╝\n\n'
}

ui_gpu_profiles() {
  while true; do
    ui_banner
    printf 'Performance Lab — GPU\n\n'
    printf 'GPU\n──────────────────────────────────────────────────────────────\n'
    printf '[ 1]  GPU Status            Telemetry + governor + OC/UV state\n'
    printf '[ 2]  Stock                 1850 MHz @ 930 mV\n'
    printf '[ 3]  Balanced              2000 MHz @ 1000 mV\n'
    printf '[ 4]  Aggressive            2100 MHz @ 1025 mV  '
    printf '%s[EXPERIMENTAL]%s\n' "${C_WARN:-}" "${C_RESET:-}"
    printf '[ 5]  Maximum Experimental  2200 MHz @ 1050 mV  '
    printf '%s[EXPERIMENTAL]%s\n' "${C_WARN:-}" "${C_RESET:-}"
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

