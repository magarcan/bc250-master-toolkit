#!/usr/bin/env bash

# YAD frontend for the BC250 Master Toolkit.
# Presentation-only layer: hardware/system operations are delegated to the
# existing CLI dispatcher. No backend functions are reimplemented here.

bc250_gui_die() {
  yad --error --title='BC250 Master Toolkit' --text="$*" --button='Close:0' 2>/dev/null || printf '%s\n' "$*" >&2
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
  [ -n "$output" ] || output='No output was returned.'
  yad --text-info \
    --title="$title" \
    --width=800 --height=560 \
    --fontname='monospace 10' \
    --text="$output" \
    --button='Close:0' 2>/dev/null
  return "$rc"
}

bc250_gui_confirm_run() {
  local title="$1" message="$2"; shift 2
  yad --question --title="$title" --width=560 --text="$message" --button='Cancel:1' --button='Apply:0' 2>/dev/null || return 1
  bc250_gui_run_output "$title" "$@"
}

bc250_gui_dashboard() {
  local status
  status=$("$ROOT/bc250-master-toolkit" status 2>&1) || true
  yad --text-info \
    --title="BC250 Master Toolkit — Dashboard" \
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
    --width=720 --height=430 \
    --text='GPU controls use the existing CLI OC/UV backend. CPU tuning is validation-only.' \
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
    'Aggressive') bc250_gui_confirm_run 'Experimental GPU Profile' 'Apply Aggressive: 2100 MHz @ 1025 mV?\n\nThis profile is marked EXPERIMENTAL.' gpu oc apply aggressive;;
    'Maximum Experimental') bc250_gui_confirm_run 'Experimental GPU Profile' 'Apply Maximum Experimental: 2200 MHz @ 1050 mV?\n\nThis profile is marked EXPERIMENTAL.' gpu oc apply maximum-experimental;;
    'Custom')
      local values freq volt minimum
      values=$(yad --form --title='Custom GPU OC/UV' --width=540 \
        --text='The existing GPU OC/UV backend performs the actual validation and apply.' \
        --field='Maximum GPU frequency (MHz):' '2000' \
        --field='Voltage (mV):' '1000' \
        --field='Minimum GPU frequency (MHz):' '600' \
        --button='Cancel:1' --button='Continue:0' 2>/dev/null) || { bc250_gui_performance; return; }
      freq=$(printf '%s' "$values" | sed -n '1p')
      volt=$(printf '%s' "$values" | sed -n '2p')
      minimum=$(printf '%s' "$values" | sed -n '3p')
      bc250_gui_confirm_run 'Apply Custom GPU OC/UV' "Apply $freq MHz @ $volt mV (minimum $minimum MHz)?" gpu oc manual "$freq" "$volt" "$minimum"
      ;;
    'Reset GPU OC/UV') bc250_gui_confirm_run 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' gpu oc reset;;
    'CPU Performance') yad --info --title='CPU Performance' --width=520 --text='CPU tuning remains in the validation/research phase.\n\nNo CPU settings are changed by this GUI.' --button='Close:0' 2>/dev/null;;
  esac
  bc250_gui_performance
}

bc250_gui_telemetry() {
  # First GUI version deliberately exposes the existing read-only status path.
  # Dedicated live telemetry controls can be added later without changing the backend.
  bc250_gui_run_output 'Hardware & Telemetry' status
  bc250_gui_dashboard
}

bc250_gui_extras() {
  yad --info \
    --title='System Extras' \
    --width=620 \
    --text='System Extras remain available through the existing CLI UI.\n\nThis first GUI layer intentionally does not duplicate or reimplement those backend actions.' \
    --button='Open CLI:10' --button='Back:0' 2>/dev/null
  if [ "$?" -eq 10 ]; then
    yad --text-info --title='System Extras — CLI' --width=820 --height=560 --fontname='monospace 10' \
      --text="Run: $ROOT/bc250-master-toolkit" --button='Close:0' 2>/dev/null
  fi
  bc250_gui_dashboard
}

bc250_gui_recovery() {
  yad --info \
    --title='Recovery & Revert' \
    --width=620 \
    --text='Recovery actions remain available through the existing CLI UI.\n\nThe GUI will only expose an action once it can delegate directly to an existing backend command.' \
    --button='Show Status:10' --button='Back:0' 2>/dev/null
  if [ "$?" -eq 10 ]; then
    bc250_gui_run_output 'System Status' status
  fi
  bc250_gui_dashboard
}

bc250_gui_main() {
  bc250_gui_require_yad || { bc250_gui_die 'YAD is required for the graphical interface.\n\nInstall it with:\nsudo pacman -S yad'; return 1; }
  bc250_gui_dashboard
}
