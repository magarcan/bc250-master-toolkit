#!/usr/bin/env bash

# Top-level UI dispatcher. Menu/action implementations live in ui.sh;
# ui_refinements.sh may override presentation/diagnostic functions before this file runs.

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
      2)
        if [ "$EUID" -eq 0 ]; then
          if [ -f /etc/default/limine.orig ]; then
            cp -a /etc/default/limine.orig /etc/default/limine
            command -v limine-update >/dev/null 2>&1 && limine-update || true
            ok 'Boot configuration restored.'
          else
            warn 'No boot configuration backup found.'
          fi
        else
          sudo bash -c 'if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; else exit 2; fi'
          [ $? -eq 0 ] && ok 'Boot configuration restored.' || warn 'No boot configuration backup found.'
        fi
        ui_pause;;
      3) ui_status; ui_pause;;
      0) return;;
    esac
  done
}

# Keep Hardware & Telemetry focused on live hardware data and diagnostics.
# CPU tuning/status belongs in Performance Lab alongside the GPU path.
ui_hardware() {
  while true; do
    ui_banner
    printf 'Hardware & Telemetry\n\n'
    printf '[ 1]  Live System Snapshot  CPU / GPU / VRM / VRAM telemetry\n'
    printf '[ 2]  Memory / UMA          Current RAM/VRAM split and recommendations\n'
    printf '[ 3]  CU / WGP              Launch BC-250 CU/WGP live manager\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) ui_live_snapshot; ui_pause;;
      2) bc250_memory_status; ui_pause;;
      3)
        if [ -x "$CU_MANAGER" ]; then
          ui_require_root cu launch
          ui_pause
        else
          bc250_cu_setup_menu_action
        fi
        ;;
      0) return;;
    esac
  done
}

# Performance Lab keeps GPU and CPU tuning symmetrical: each has a status
# entry first, followed by its validated tuning/profile actions.
ui_cpu_performance() {
  while true; do
    ui_banner
    printf 'Performance Lab — CPU\n\n'
    printf 'CPU\n──────────────────────────────────────────────────────────────\n'
    printf '[ 1]  CPU Status            Topology + frequency + driver + governor\n'
    printf '[ 2]  CPU Tuning            Reserved for validated CPU tuning\n'
    printf '[ 0]  Back\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      1) bc250_cpu_status; ui_pause;;
      2) ui_banner; printf 'CPU Tuning\n\n'; info 'CPU tuning remains in the validation/research phase. No settings are changed here yet.'; ui_pause;;
      0) return;;
    esac
  done
}

ui_menu() {
  while true; do
    ui_banner
    printf 'Validation\n──────────────────────────────────────────────────────────────\n'
    printf '[ P]  Preflight             Validate and configure missing components\n\n'
    printf 'Platform\n──────────────────────────────────────────────────────────────\n'
    printf '[ 1]  Performance Lab       GPU status, profiles and CPU tuning\n'
    printf '[ 2]  Hardware & Telemetry  Live measurements and diagnostics\n'
    printf '[ 3]  System Extras         Status + optional system changes\n'
    printf '[ 4]  Recovery & Revert     Undo supported changes\n\n'
    printf 'System\n──────────────────────────────────────────────────────────────\n'
    printf '[ S]  Status                Current system summary\n'
    printf '[ U]  Update Toolkit        Update from GitHub checkout\n'
    printf '[ 0]  Exit\n\nEnter selection: '
    read -r s
    case "${s,,}" in
      p) ui_preflight; ui_pause;;
      s) ui_status; ui_pause;;
      1) ui_performance;;
      2) ui_hardware;;
      3) ui_extras;;
      4) ui_recovery;;
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
            profiles)
              printf 'Stock 1850 MHz @ 930 mV\n'
              printf 'Balanced 2000 MHz @ 1000 mV\n'
              printf 'Aggressive 2100 MHz @ 1025 mV [EXPERIMENTAL]\n'
              printf 'Maximum Experimental 2200 MHz @ 1050 mV [EXPERIMENTAL]\n'
              ;;
            status) bc250_gpu_oc_status;;
            apply) ui_require_root gpu oc apply "${4:-}";;
            manual) ui_require_root gpu oc manual "${4:-}" "${5:-}" "${6:-}";;
            reset) ui_require_root gpu oc reset;;
            *) die 'Unknown GPU OC command.'; return 1;;
          esac
          ;;
        *) die 'Unknown GPU command.'; return 1;;
      esac
      ;;
    *) die "Unknown command: ${1:-}"; return 1;;
  esac
}
