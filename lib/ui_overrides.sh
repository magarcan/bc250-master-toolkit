#!/usr/bin/env bash

# Loaded last so the interactive UI can override the low-level dispatch helpers.
root_action() {
  case "${2:-}" in
    kernel-install) bc250_kernel_install ;;
    gpu-oc-apply) bc250_gpu_oc_apply "${3:-}" ;;
    gpu-oc-manual) bc250_gpu_oc_manual "${3:-}" "${4:-}" "${5:-}" ;;
    gpu-oc-reset) bc250_gpu_oc_reset ;;
    *) die "Unknown privileged action: ${2:-}" ;;
  esac
}

performance_menu(){
  while true; do
    banner; heading 'Performance Profiles'; echo
    printf 'GPU profiles — Cyan-Skillfish Governor SMU\n\n'
    bc250_gpu_oc_status 2>/dev/null || true
    echo
    printf '[ 1]  Stock                  Apply stock GPU profile\n'
    printf '[ 2]  Balanced               Apply balanced GPU profile\n'
    printf '[ 3]  Aggressive             Apply aggressive GPU profile\n'
    printf '[ 4]  Maximum Experimental   Apply maximum experimental profile\n'
    printf '[ C]  Custom                 Enter GPU frequency and voltage\n'
    printf '[ 0]  Back\n\n'
    printf 'Enter selection: '; read -r s
    case "${s,,}" in
      1) bc250_setup_require_root gpu-oc-apply stock; read -r -p 'Press Enter to continue...' _ ;;
      2) bc250_setup_require_root gpu-oc-apply balanced; read -r -p 'Press Enter to continue...' _ ;;
      3) bc250_setup_require_root gpu-oc-apply aggressive; read -r -p 'Press Enter to continue...' _ ;;
      4) bc250_setup_require_root gpu-oc-apply maximum-experimental; read -r -p 'Press Enter to continue...' _ ;;
      c) printf 'Maximum frequency (MHz): '; read -r f; printf 'Voltage (mV): '; read -r v; bc250_setup_require_root gpu-oc-manual "$f" "$v"; read -r -p 'Press Enter to continue...' _ ;;
      0) return ;;
    esac
  done
}
