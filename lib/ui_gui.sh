#!/usr/bin/env bash

# YAD frontend for the BC250 Master Toolkit.
# This file is presentation-only: all hardware/system operations are delegated
# to the existing CLI dispatcher in bc250-master-toolkit.

bc250_gui_die() {
  yad --error --title='BC250 Master Toolkit' --text="$*" --button='Close:0" 2>/dev/null || printf '%s\n' "$*" >&2
}

bc250_gui_require_yad() {
  command -v yad >/dev/null 2>&1 && return 0
  printf '%s\n' 'YAD is not installed. Install it with: sudo pacman -S yad' >&2
  return 1
}

bc250_gui_run_output() {
  local title="$1"; shift
  local output rc
  output=$("$ROOT/bc250-master-toolkit" "$@" 2>&1)
  rc=$?
  if [ -z "$output" ]; then
    output='No output was returned.'
  fi
  if [ "$rc" -eq 0 ]; then
    yad --text-info --title="$title" --width=760 --height=560 --fontname='monospace 10' --text="$output" --button='Close:0' 2>/dev/null
  else
    yad --text-info --title="$title — action failed" --width=760 --height=560 --fontname='monospace 10' --text="$output" --button='Close:0' 2>/dev/null
  fi
  return "$rc"
}

bc250_gui_confirm_run() {
  local title="$1" message="$2"; shift 2
  yad --question --title="$title" --width=520 --text="$message" --button='Cancel:1' --button='Apply:0' 2>/dev/null || return 1
  bc250_gui_run_output "$title" "$@"
}

bc250_gui_dashboard() {
  local status
  status=$("$ROOT/bc250-master-toolkit" status 2>&1) || true
  yad --text-info \
    --title='BC250 Master Toolkit — Dashboard' \
    --width=820 --height=560 \
    --fontname='monospace 10' \
    --text="$status" \
    --button='Preflight:10' \
    --button='Performance Lab:11' \
    --button='Telemetry:12' \
    --button='System Extras:13' \
    --button='Recovery:14' \
    --button='Refresh:15' \
    --button='Close:0' 2>/dev/null
  case "$?" in
    10) bc250_gui_preflight;;
    11) bc250_gui_performance;;
    12) bc250_gui_telemetry;;
    13) bc250_gui_extras;;
    14) bc250_gui_recovery;;
    15) bc250_gui_dashboard;;
  esac
}

bc250_gui_preflight() {
  bc250_gui_run_output 'Platform Preflight' preflight
  bc250_gui_dashboard
}

bc250_gui_performance() {
  local choice
  choice=$(yad --list --radiolist \
    --title='BC250 Master Toolkit — Performance Lab' \
    --width=700 --height=430 \
    --text='GPU performance controls. CPU tuning remains validation-only.' \
    --column='' --column='Action' --column='Setting' \
    TRUE 'GPU Status' 'Telemetry + governor + OC/UV state' \
    FALSE 'Stock' '1850 MHz @ 930 mV' \
    FALSE 'Balanced' '2000 MHz @ 1000 mV' \
    FALSE 'Aggressive' '2100 MHz @ 1025 mV — EXPERIMENTAL' \
    FALSE 'Maximum Experimental' '2200 MHz @ 1050 mV — EXPERIMENTAL' \
    FALSE 'Custom' 'Enter frequency / voltage / minimum frequency' \
    FALSE 'Reset GPU OC/UV' 'Restore saved GPU configuration' \
    FALSE 'CPU Performance' 'Reserved for validated CPU tuning' \
    --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || { bc250_gui_dashboard; return; }

  case "$choice" in
    'GPU Status') bc250_gui_run_output 'GPU Status' gpu status;;
    'Stock') bc250_gui_confirm_run 'Apply Stock GPU Profile' 'Apply Stock: 1850 MHz @ 930 mV?' gpu oc apply stock;;
    'Balanced') bc250_gui_confirm_run 'Apply Balanced GPU Profile' 'Apply Balanced: 2000 MHz @ 1000 mV?' gpu oc apply balanced;;
    'Aggressive') bc250_gui_confirm_run 'Experimental GPU Profile' 'Apply Aggressive: 2100 MHz @ 1025 mV?\n\nThis is marked EXPERIMENTAL.' gpu oc apply aggressive;;
    'Maximum Experimental') bc250_gui_confirm_run 'Experimental GPU Profile' 'Apply Maximum Experimental: 2200 MHz @ 1050 mV?\n\nThis is marked EXPERIMENTAL.' gpu oc apply maximum-experimental;;
    'Custom')
      local values freq volt minimum
      values=$(yad --form --title='Custom GPU OC/UV' --width=520 --text='Validate the requested operating point before applying it.' \
        --field='Maximum GPU frequency (MHz):' '2000' \
        --field='Voltage (mV):' '1000' \
        --field='Minimum GPU frequency (MHz):' '600' \
        --button='Cancel:1' --button='Continue:0' 2>/dev/null) || { bc250_gui_performance; return; }
      freq=$(printf '%s' "$values" | sed -n '1p'); volt=$(printf '%s' "$values" | sed -n '2p'); minimum=$(printf '%s' "$values" | sed -n '3p')
      bc250_gui_confirm_run 'Apply Custom GPU OC/UV' "Apply $freq MHz @ $volt mV (minimum $minimum MHz)?" gpu oc manual "$freq" "$volt" "$minimum"
      ;;
    'Reset GPU OC/UV') bc250_gui_confirm_run 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' gpu oc reset;;
    'CPU Performance') yad --info --title='CPU Performance' --text='CPU tuning remains in the validation/research phase.\n\nNo CPU settings are changed by the GUI.' --button='Close:0' 2>/dev/null;;
  esac
  bc250_gui_performance
}

bc250_gui_telemetry() {
  bc250_gui_run_output 'Hardware & Telemetry' status
  bc250_gui_dashboard
}

bc250_gui_extras() {
  local choice
  choice=$(yad --list --radiolist \
    --title='BC250 Master Toolkit — System Extras' \
    --width=720 --height=430 \
    --text='Optional system changes. Current state is always shown before an action.' \
    --column='' --column='Action' --column='Description' \
    TRUE 'Refresh Status' 'Re-check current system state' \
    FALSE 'Enable Swap' 'Persistent 16G swapfile by default' \
    FALSE 'Enable ZSWAP' 'Disable systemd ZRAM and enable compressed swap' \
    FALSE 'Hide RDSEED Warning' 'Set boot loglevel=0' \
    FALSE 'Disable CPU Mitigations' 'Add mitigations=off to boot configuration' \
    FALSE 'CU / WGP + UMR' 'Open compute-unit tools and diagnostics' \
    --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || { bc250_gui_dashboard; return; }

  case "$choice" in
    'Refresh Status') bc250_gui_run_output 'System Extras — Current State' status;;
    'Enable Swap') bc250_gui_confirm_run 'Enable Swap' 'Enable the persistent 16G swapfile?' extras swap enable 16G;;
    'Enable ZSWAP') bc250_gui_confirm_run 'Enable ZSWAP' 'Enable ZSWAP and disable systemd ZRAM?' extras zswap enable;;
    'Hide RDSEED Warning') bc250_gui_confirm_run 'Hide RDSEED Warning' 'Set boot loglevel=0 to hide the RDSEED warning?' extras rdseed hide;;
    'Disable CPU Mitigations') bc250_gui_confirm_run 'Disable CPU Mitigations' 'Add mitigations=off to the boot configuration?\n\nThis reduces security protections.' extras mitigations off;;
    'CU / WGP + UMR') bc250_gui_run_output 'CU / WGP + UMR' cu status;;
  esac
  bc250_gui_extras
}

bc250_gui_recovery() {
  local choice
  choice=$(yad --list --radiolist \
    --title='BC250 Master Toolkit — Recovery & Revert' \
    --width=700 --height=350 \
    --text='Supported recovery actions.' \
    --column='' --column='Action' --column='Description' \
    TRUE 'Reset GPU OC/UV' 'Restore saved GPU configuration' \
    FALSE 'Show System Status' 'Inspect current state before reverting' \
    FALSE 'Restore Boot Configuration' 'Restore toolkit backup when available' \
    --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || { bc250_gui_dashboard; return; }

  case "$choice" in
    'Reset GPU OC/UV') bc250_gui_confirm_run 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' gpu oc reset;;
    'Show System Status') bc250_gui_run_output 'System Status' status;;
    'Restore Boot Configuration')
      yad --question --title='Restore Boot Configuration' --width=560 --text='Restore /etc/default/limine from the toolkit backup when available?' --button='Cancel:1' --button='Restore:0' 2>/dev/null && \
        bc250_gui_run_output 'Restore Boot Configuration' bash -c 'if [ "$EUID" -eq 0 ]; then if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot configuration backup found."; exit 1; fi; else sudo bash -c '\''if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot configuration backup found."; exit 1; fi'\''; fi'
      ;;
  esac
  bc250_gui_recovery
}

bc250_gui_main() {
  bc250_gui_require_yad || { bc250_gui_die 'YAD is required for the graphical interface.\n\nInstall it with:\nsudo pacman -S yad'; return 1; }
  bc250_gui_dashboard
}
