#!/usr/bin/env bash

# YAD frontend for the BC250 Master Toolkit.
# Presentation-only layer: all hardware/system operations are delegated to
# functions already loaded by the CLI. No backend hardware logic lives here.

BC250_GUI_TITLE='BC250 Master Toolkit'
BC250_GUI_WIDTH=820
BC250_GUI_HEIGHT=560

bc250_gui_require_yad() {
  command -v yad >/dev/null 2>&1 && return 0
  printf '%s\n' 'YAD is not installed. Install it with: sudo pacman -S yad' >&2
  return 1
}

bc250_gui_error() {
  yad --error --title="$BC250_GUI_TITLE" --width=500 --text="$*" --button='Close:0' 2>/dev/null || true
}

bc250_gui_info() {
  local title="$1" text="$2"
  yad --info --title="$title" --width=560 --text="$text" --button='Close:0' 2>/dev/null || true
}

bc250_gui_text() {
  local title="$1" content="$2"
  printf '%s\n' "$content" | yad --text-info --title="$title" \
    --width="$BC250_GUI_WIDTH" --height="$BC250_GUI_HEIGHT" \
    --fontname='monospace 10' --wrap --button='Close:0' 2>/dev/null || true
}

bc250_gui_capture_function() {
  local fn="$1"; shift
  local output rc
  output=$(NO_COLOR=1 "$fn" "$@" 2>&1)
  rc=$?
  printf '%s' "$output"
  return "$rc"
}

bc250_gui_run_function() {
  local title="$1" fn="$2"; shift 2
  local output rc
  output=$(bc250_gui_capture_function "$fn" "$@")
  rc=$?
  [ -n "$output" ] || output='No output was returned.'
  bc250_gui_text "$title" "$output"
  return "$rc"
}

bc250_gui_confirm_function() {
  local title="$1" message="$2" fn="$3"; shift 3
  yad --question --title="$title" --width=560 --text="$message" \
    --button='Cancel:1' --button='Apply:0' 2>/dev/null || return 1
  bc250_gui_run_function "$title" "$fn" "$@"
}

bc250_gui_preflight_output() {
  # ui_preflight is the canonical validator. Feed "n" so an incomplete system
  # is reported without entering the CLI assisted-setup prompt inside YAD.
  printf 'n\n' | NO_COLOR=1 ui_preflight 2>&1
}

bc250_gui_dashboard() {
  while true; do
    local card h vr bios kernel cores threads driver governor cpu_freq cpu_temp
    local gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp platform
    card=$(bc250_gpu_card 2>/dev/null || true)
    bios=$(bc250_bios); kernel=$(uname -r); cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
    driver=$(bc250_cpu_driver); governor=$(bc250_cpu_governor); cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp)
    if [[ "$card" == card* ]]; then
      h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card")
      gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card"); gpu_temp=$(bc250_gpu_temp "$h")
      gpu_mclk=$(bc250_gpu_mclk "$h"); vr_used=${vr% *}; vr_total=${vr#* }; vrm_temp=$(bc250_vrm_temp)
    else
      card='Not detected'; gpu_sclk=N/A; gpu_busy=N/A; gpu_temp=N/A; gpu_mclk=N/A; vr_used=N/A; vr_total=N/A; vrm_temp=$(bc250_vrm_temp)
    fi
    if bc250_bios_ok && bc250_kernel_ok && [ "$cores" -ge 8 ] 2>/dev/null && [ "$threads" -ge 16 ] 2>/dev/null; then platform='READY'; else platform='CHECK PREFLIGHT'; fi

    yad --form --title="$BC250_GUI_TITLE — Dashboard" --width=850 --height=520 \
      --text="<b>BC250 platform overview</b>    Toolkit v${VERSION}    Platform: <b>${platform}</b>" \
      --columns=2 \
      --field='BIOS:RO' "$bios" \
      --field='Kernel:RO' "$kernel" \
      --field='CPU topology:RO' "${cores}C / ${threads}T" \
      --field='CPU driver:RO' "$driver" \
      --field='CPU governor:RO' "$governor" \
      --field='CPU frequency:RO' "${cpu_freq} MHz" \
      --field='CPU temperature:RO' "${cpu_temp} °C" \
      --field='GPU device:RO' "$card" \
      --field='GPU SCLK:RO' "${gpu_sclk} MHz" \
      --field='GPU load:RO' "${gpu_busy} %" \
      --field='GPU temperature:RO' "${gpu_temp} °C" \
      --field='GPU MCLK:RO' "${gpu_mclk} MHz" \
      --field='VRAM:RO' "${vr_used} / ${vr_total} MB" \
      --field='VRM temperature:RO' "${vrm_temp} °C" \
      --button='Preflight:10' --button='Platform Setup:11' --button='Performance Lab:12' \
      --button='Hardware & Telemetry:13' --button='System Extras:14' --button='Recovery:15' \
      --button='Refresh:16' --button='Close:0' 2>/dev/null
    case $? in
      10) bc250_gui_preflight;;
      11) bc250_gui_platform;;
      12) bc250_gui_performance;;
      13) bc250_gui_hardware;;
      14) bc250_gui_extras;;
      15) bc250_gui_recovery;;
      16) continue;;
      *) return 0;;
    esac
  done
}

bc250_gui_preflight() {
  local output
  output=$(bc250_gui_preflight_output)
  bc250_gui_text 'BC250 Master Toolkit — Preflight' "$output"
}

bc250_gui_platform() {
  while true; do
    local bios_state kernel_state gov_state cu_state umr_state choice
    bc250_bios_ok && bios_state='OK — P3.00' || bios_state="WARN — $(bc250_bios)"
    bc250_kernel_ok && kernel_state="OK — $(uname -r)" || kernel_state="WARN — $(uname -r)"
    bc250_governor_ok && gov_state='OK — service active' || gov_state='WARN — service inactive'
    [ -x /usr/local/bin/bc250-cu-live-manager ] && cu_state='OK — installed' || cu_state='WARN — missing'
    bc250_umr_present && umr_state='OK — available' || umr_state='WARN — missing'

    choice=$(yad --list --radiolist --title="$BC250_GUI_TITLE — Platform Setup" \
      --width=780 --height=470 --text='<b>Platform prerequisites</b> — inspect state first, then run only the required action.' \
      --column='' --column='Component' --column='Current state' --column='Action' \
      TRUE 'Preflight' 'Full platform validation' 'Run validation' \
      FALSE 'BIOS' "$bios_state" 'Open firmware reference if needed' \
      FALSE 'CachyOS BC-250 Kernel' "$kernel_state" 'Install recommended kernel if needed' \
      FALSE 'GPU Governor' "$gov_state" 'Inspect governor / GPU state' \
      FALSE 'CU / WGP Manager' "$cu_state" 'Install/update manager' \
      FALSE 'UMR' "$umr_state" 'Install diagnostic dependency' \
      --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || return 0

    case "$choice" in
      'Preflight') bc250_gui_preflight;;
      'BIOS')
        if bc250_bios_ok; then
          bc250_gui_info 'BIOS' "BIOS P3.00 is already active.\n\nNo firmware action is required."
        else
          yad --question --title='BIOS Recommendation' --width=580 \
            --text="Detected BIOS: $(bc250_bios)\nRecommended: P3.00\n\nThe toolkit will not flash the BIOS. Open the upstream firmware project?" \
            --button='Cancel:1' --button='Open project:0' 2>/dev/null && xdg-open "$BC250_BIOS_URL" >/dev/null 2>&1 &
        fi
        ;;
      'CachyOS BC-250 Kernel')
        if bc250_kernel_ok; then
          bc250_gui_info 'BC-250 Kernel' "The active kernel already contains the BC-250 marker:\n$(uname -r)"
        else
          bc250_gui_confirm_function 'Install BC-250 Kernel' \
            "Install linux-cachyos-bc250 and matching headers?\n\nA reboot will be required." \
            bc250_setup_require_root kernel-install
        fi
        ;;
      'GPU Governor') bc250_gui_run_function 'GPU Governor / Status' ui_gpu_status;;
      'CU / WGP Manager')
        if ! bc250_umr_present; then
          yad --question --title='CU / WGP Setup' --width=560 \
            --text='UMR is required by the CU/WGP manager and is currently missing. Install UMR first?' \
            --button='Cancel:1' --button='Install UMR:0' 2>/dev/null || continue
          bc250_gui_run_function 'Install UMR' bc250_setup_require_root umr-install || continue
        fi
        bc250_gui_confirm_function 'Install CU / WGP Manager' 'Install or update the CU/WGP manager?' bc250_setup_require_root cu-install
        ;;
      'UMR')
        if bc250_umr_present; then
          bc250_gui_info 'UMR' "UMR is already available:\n$(command -v umr)"
        else
          bc250_gui_confirm_function 'Install UMR' 'Download, build and install UMR from the configured upstream source?' bc250_setup_require_root umr-install
        fi
        ;;
    esac
  done
}

bc250_gui_performance() {
  while true; do
    local choice
    choice=$(yad --list --radiolist --title="$BC250_GUI_TITLE — Performance Lab" \
      --width=760 --height=480 \
      --text='<b>GPU Performance</b> — validated profiles use the existing Cyan-Skillfish OC/UV backend. CPU tuning remains validation-only.' \
      --column='' --column='Action' --column='Setting' \
      TRUE 'GPU Status' 'Telemetry + governor + OC/UV state' \
      FALSE 'Stock' '1850 MHz @ 930 mV' \
      FALSE 'Balanced' '2000 MHz @ 1000 mV' \
      FALSE 'Aggressive' '2100 MHz @ 1025 mV — EXPERIMENTAL' \
      FALSE 'Maximum Experimental' '2200 MHz @ 1050 mV — EXPERIMENTAL' \
      FALSE 'Custom' 'Enter maximum frequency / voltage / minimum frequency' \
      FALSE 'Reset GPU OC/UV' 'Restore saved GPU configuration' \
      FALSE 'CPU Performance' 'Reserved for validated CPU tuning' \
      --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || return 0

    case "$choice" in
      'GPU Status') bc250_gui_run_function 'GPU Status' ui_gpu_status;;
      'Stock') bc250_gui_confirm_function 'Apply Stock GPU Profile' 'Apply Stock: 1850 MHz @ 930 mV?' ui_require_root gpu oc apply stock;;
      'Balanced') bc250_gui_confirm_function 'Apply Balanced GPU Profile' 'Apply Balanced: 2000 MHz @ 1000 mV?' ui_require_root gpu oc apply balanced;;
      'Aggressive') bc250_gui_confirm_function 'Experimental GPU Profile' 'Apply Aggressive: 2100 MHz @ 1025 mV?\n\nThis profile is EXPERIMENTAL.' ui_require_root gpu oc apply aggressive;;
      'Maximum Experimental') bc250_gui_confirm_function 'Experimental GPU Profile' 'Apply Maximum Experimental: 2200 MHz @ 1050 mV?\n\nThis profile is EXPERIMENTAL.' ui_require_root gpu oc apply maximum-experimental;;
      'Custom')
        local values freq volt minimum
        values=$(yad --form --title='Custom GPU OC/UV' --width=540 \
          --text='Enter the requested operating point. The existing backend performs the actual validation/application.' \
          --field='Maximum GPU frequency (MHz):NUM' '2000!600..2400!1' \
          --field='Voltage (mV):NUM' '1000!800..1200!1' \
          --field='Minimum GPU frequency (MHz):NUM' '600!300..2200!1' \
          --separator='|' --button='Cancel:1' --button='Continue:0' 2>/dev/null) || continue
        IFS='|' read -r freq volt minimum _ <<< "$values"
        freq=${freq%.*}; volt=${volt%.*}; minimum=${minimum%.*}
        bc250_gui_confirm_function 'Apply Custom GPU OC/UV' \
          "Apply ${freq} MHz @ ${volt} mV (minimum ${minimum} MHz)?" \
          ui_require_root gpu oc manual "$freq" "$volt" "$minimum"
        ;;
      'Reset GPU OC/UV') bc250_gui_confirm_function 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' ui_require_root gpu oc reset;;
      'CPU Performance') bc250_gui_info 'CPU Performance' 'CPU tuning remains in the validation/research phase.\n\nNo CPU settings are changed here yet.';;
    esac
  done
}

bc250_gui_live_snapshot() {
  while true; do
    local card h vr load result
    local cpu_freq cpu_temp cores threads gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp
    card=$(bc250_gpu_card 2>/dev/null || true)
    if [[ "$card" != card* ]]; then bc250_gui_error 'BC-250 GPU not detected.'; return 1; fi
    h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card"); load=$(ui_cpu_load_percent)
    cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp); cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
    gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card"); gpu_temp=$(bc250_gpu_temp "$h"); gpu_mclk=$(bc250_gpu_mclk "$h")
    vr_used=${vr% *}; vr_total=${vr#* }; vrm_temp=$(bc250_vrm_temp)
    yad --form --title="$BC250_GUI_TITLE — Live Telemetry" --width=720 --height=430 --columns=2 \
      --text='<b>Live system snapshot</b> — press Refresh to sample again.' \
      --field='CPU load:RO' "${load} %" \
      --field='CPU frequency:RO' "${cpu_freq} MHz" \
      --field='CPU temperature:RO' "${cpu_temp} °C" \
      --field='CPU topology:RO' "${cores}C / ${threads}T" \
      --field='GPU device:RO' "$card" \
      --field='GPU SCLK:RO' "${gpu_sclk} MHz" \
      --field='GPU load:RO' "${gpu_busy} %" \
      --field='GPU temperature:RO' "${gpu_temp} °C" \
      --field='GPU MCLK:RO' "${gpu_mclk} MHz" \
      --field='VRAM usage:RO' "${vr_used} / ${vr_total} MB" \
      --field='VRM temperature:RO' "${vrm_temp} °C" \
      --button='Refresh:10' --button='Close:0' 2>/dev/null
    result=$?
    [ "$result" -eq 10 ] || return 0
  done
}

bc250_gui_memory() {
  local mem total avail used vused vtotal rec
  mem=$(bc250_memory_status); read -r total avail vused vtotal <<< "$mem"; used=$((total-avail))
  rec=$(bc250_memory_recommendations)
  yad --form --title="$BC250_GUI_TITLE — Memory / UMA" --width=700 --height=430 \
    --text='<b>Memory / UMA</b> — informational only. The toolkit does not change the BIOS UMA split.' \
    --field='System RAM total:RO' "${total} MB" \
    --field='System RAM used:RO' "${used} MB" \
    --field='System RAM available:RO' "${avail} MB" \
    --field='VRAM used:RO' "${vused} MB" \
    --field='VRAM total:RO' "${vtotal} MB" \
    --field='Workload recommendations:TXT' "$rec" \
    --button='Close:0' 2>/dev/null || true
}

bc250_gui_cpu_diagnostics() {
  local load
  load=$(ui_cpu_load_percent)
  yad --form --title="$BC250_GUI_TITLE — CPU Diagnostics" --width=680 --height=390 --columns=2 \
    --text='<b>CPU diagnostics</b>' \
    --field='Cores / Threads:RO' "$(bc250_cpu_cores)C / $(bc250_cpu_threads)T" \
    --field='Driver:RO' "$(bc250_cpu_driver)" \
    --field='Governor:RO' "$(bc250_cpu_governor)" \
    --field='Current frequency:RO' "$(bc250_cpu_freq) MHz" \
    --field='Load:RO' "${load} %" \
    --field='Temperature:RO' "$(bc250_cpu_temp) °C" \
    --button='Close:0' 2>/dev/null || true
}

bc250_gui_hardware() {
  while true; do
    local choice
    choice=$(yad --list --radiolist --title="$BC250_GUI_TITLE — Hardware & Telemetry" \
      --width=720 --height=400 --text='<b>Diagnostics and measurements</b>' \
      --column='' --column='View' --column='Description' \
      TRUE 'Live System Snapshot' 'CPU / GPU / VRM / VRAM live measurements' \
      FALSE 'Memory / UMA' 'Current RAM/VRAM split and recommendations' \
      FALSE 'CU / WGP' 'Compute-unit state and UMR diagnostics' \
      FALSE 'CPU Diagnostics' 'Topology, driver, governor, load and thermals' \
      --print-column=2 --button='Back:0' --button='Open:10' 2>/dev/null) || return 0
    case "$choice" in
      'Live System Snapshot') bc250_gui_live_snapshot;;
      'Memory / UMA') bc250_gui_memory;;
      'CU / WGP') bc250_gui_run_function 'CU / WGP Diagnostics' bc250_cu_status;;
      'CPU Diagnostics') bc250_gui_cpu_diagnostics;;
    esac
  done
}

bc250_gui_extras() {
  while true; do
    local zswap zram swap_state conf rdseed mitigations choice
    zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N)
    [ -e /dev/zram0 ] && zram='Active' || zram='Not exposed'
    if swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {found=1} END{exit !found}'; then swap_state='Enabled'; else swap_state='Not configured'; fi
    conf=$(bc250_boot_conf 2>/dev/null || echo 'Not found')
    rdseed='Default'; mitigations='Default'
    [ -f "$conf" ] && grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed='Hidden'
    [ -f "$conf" ] && grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations='DISABLED'

    choice=$(yad --list --radiolist --title="$BC250_GUI_TITLE — System Extras" \
      --width=820 --height=480 \
      --text="<b>Current state</b>   Swap: ${swap_state}   |   ZRAM: ${zram}   |   ZSWAP: $([ "$zswap" = Y ] && echo Enabled || echo Disabled)\nBoot: ${conf}   |   RDSEED: ${rdseed}   |   Mitigations: ${mitigations}" \
      --column='' --column='Action' --column='Description' \
      TRUE 'Show Detailed Status' 'Display the canonical Extras status view' \
      FALSE 'Enable Swap' 'Persistent 16G swapfile by default' \
      FALSE 'Enable ZSWAP' 'Disable systemd ZRAM and enable compressed swap' \
      FALSE 'Hide RDSEED Warning' 'Set boot loglevel=0' \
      FALSE 'Disable CPU Mitigations' 'Add mitigations=off to boot configuration' \
      FALSE 'CU / WGP + UMR' 'Compute-unit tools and diagnostics' \
      --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || return 0

    case "$choice" in
      'Show Detailed Status') bc250_gui_run_function 'System Extras — Current State' ui_extras_status;;
      'Enable Swap') bc250_gui_confirm_function 'Enable Swap' 'Enable the persistent 16G swapfile?' ui_require_root extras swap enable 16G;;
      'Enable ZSWAP') bc250_gui_confirm_function 'Enable ZSWAP' 'Enable ZSWAP and disable systemd ZRAM?\n\nA reboot may be required for the complete boot-time configuration.' ui_require_root extras zswap enable;;
      'Hide RDSEED Warning') bc250_gui_confirm_function 'Hide RDSEED Warning' 'Set boot loglevel=0 to hide the RDSEED warning?' ui_require_root extras rdseed hide;;
      'Disable CPU Mitigations') bc250_gui_confirm_function 'Disable CPU Mitigations' 'Add mitigations=off to the boot configuration?\n\nThis reduces security protections.' ui_require_root extras mitigations off;;
      'CU / WGP + UMR') bc250_gui_run_function 'CU / WGP + UMR' bc250_cu_status;;
    esac
  done
}

bc250_gui_restore_boot() {
  yad --question --title='Restore Boot Configuration' --width=580 \
    --text='Restore /etc/default/limine from /etc/default/limine.orig when available?' \
    --button='Cancel:1' --button='Restore:0' 2>/dev/null || return 1
  local output rc
  output=$(sudo bash -c 'if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot configuration backup found."; exit 2; fi' 2>&1)
  rc=$?; bc250_gui_text 'Restore Boot Configuration' "$output"; return "$rc"
}

bc250_gui_recovery() {
  while true; do
    local choice
    choice=$(yad --list --radiolist --title="$BC250_GUI_TITLE — Recovery & Revert" \
      --width=720 --height=390 --text='<b>Supported rollback paths</b>' \
      --column='' --column='Action' --column='Description' \
      TRUE 'Reset GPU OC/UV' 'Restore saved GPU configuration' \
      FALSE 'Restore Boot Configuration' 'Restore toolkit backup when available' \
      FALSE 'Show System Status' 'Inspect current state before reverting' \
      --print-column=2 --button='Back:0' --button='Select:10' 2>/dev/null) || return 0
    case "$choice" in
      'Reset GPU OC/UV') bc250_gui_confirm_function 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' ui_require_root gpu oc reset;;
      'Restore Boot Configuration') bc250_gui_restore_boot;;
      'Show System Status') bc250_gui_run_function 'System Status' ui_status;;
    esac
  done
}

bc250_gui_main() {
  bc250_gui_require_yad || {
    printf '%s\n' 'YAD is required for the graphical interface.' >&2
    return 1
  }
  bc250_gui_dashboard
}
