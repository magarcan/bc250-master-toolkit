#!/usr/bin/env bash

# YAD frontend for the BC250 Master Toolkit.
# Presentation-only layer: all hardware/system operations are delegated to
# functions already loaded by the CLI. No backend hardware logic lives here.

BC250_GUI_TITLE='BC250 Master Toolkit'
BC250_GUI_WIDTH=900
BC250_GUI_HEIGHT=600
BC250_GUI_OK="<span foreground='#70d890'><b>● OK</b></span>"
BC250_GUI_WARN="<span foreground='#f0c75e'><b>● ACTION REQUIRED</b></span>"
BC250_GUI_INFO="<span foreground='#63c7e6'><b>● INFO</b></span>"

bc250_gui_require_yad() {
  command -v yad >/dev/null 2>&1 && return 0
  printf '%s\n' 'YAD is not installed. Install it with: sudo pacman -S yad' >&2
  return 1
}

bc250_gui_error() {
  yad --error --title="$BC250_GUI_TITLE" --width=520 --text="$*" --button='Close:0' 2>/dev/null || true
}

bc250_gui_info() {
  local title="$1" text="$2"
  yad --info --title="$title" --width=600 --text="$text" --button='Close:0' 2>/dev/null || true
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
  yad --question --title="$title" --width=600 --text="$message" \
    --button='Cancel:1' --button='Apply:0' 2>/dev/null || return 1
  bc250_gui_run_function "$title" "$fn" "$@"
}

bc250_gui_status_markup() {
  local state="$1"
  case "$state" in
    OK*) printf '%s' "$BC250_GUI_OK";;
    WARN*|MISSING*|INACTIVE*) printf '%s' "$BC250_GUI_WARN";;
    *) printf '%s' "$BC250_GUI_INFO";;
  esac
}

bc250_gui_dashboard() {
  while true; do
    local card bios kernel cores threads driver governor cpu_freq cpu_temp
    local gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp platform
    card=$(bc250_gpu_card 2>/dev/null || true)
    bios=$(bc250_bios 2>/dev/null || echo 'Unknown')
    kernel=$(uname -r)
    cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
    driver=$(bc250_cpu_driver); governor=$(bc250_cpu_governor)
    cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp)
    gpu_sclk=N/A; gpu_busy=N/A; gpu_temp=N/A; gpu_mclk=N/A; vr_used=N/A; vr_total=N/A
    vrm_temp=$(bc250_vrm_temp 2>/dev/null || echo N/A)
    if [[ "$card" == card* ]]; then
      local h vr
      h=$(bc250_hwmon "$card" 2>/dev/null || true)
      vr=$(bc250_gpu_vram "$card" 2>/dev/null || echo 'N/A N/A')
      gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card")
      gpu_temp=$(bc250_gpu_temp "$h"); gpu_mclk=$(bc250_gpu_mclk "$h")
      vr_used=${vr% *}; vr_total=${vr#* }
    else
      card='Not detected'
    fi
    if bc250_bios_ok && bc250_kernel_ok && [ "$cores" -ge 8 ] 2>/dev/null && [ "$threads" -ge 16 ] 2>/dev/null; then
      platform='READY'
    else
      platform='CHECK PREFLIGHT'
    fi

    yad --form --title="$BC250_GUI_TITLE — Dashboard" --width=920 --height=620 \
      --text="<b>BC250 PLATFORM CONTROL CENTER</b>    v${VERSION}    Platform: <b>${platform}</b>\nLive overview of the validated platform state and current telemetry." \
      --columns=2 --separator='|' \
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
      --button='Preflight:10' --button='Platform Setup:11' --button='Performance:12' \
      --button='Telemetry:13' --button='Extras:14' --button='Recovery:15' \
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

bc250_gui_preflight_rows() {
  local card bios kernel cores threads
  card=$(bc250_gpu_card 2>/dev/null || true)
  bios=$(bc250_bios 2>/dev/null || echo Unknown)
  kernel=$(uname -r)
  cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)

  if [[ "$card" == card* ]]; then printf 'TRUE|%s|AMD BC-250 GPU|PCI 1002:13fe|Detected\n' "$BC250_GUI_OK"; else printf 'TRUE|%s|AMD BC-250 GPU|PCI 1002:13fe|Not detected\n' "$BC250_GUI_WARN"; fi
  if bc250_bios_ok; then printf 'FALSE|%s|BIOS|%s|P3.00 active\n' "$BC250_GUI_OK" "$bios"; else printf 'FALSE|%s|BIOS|%s|P3.00 recommended\n' "$BC250_GUI_WARN" "$bios"; fi
  if bc250_kernel_ok; then printf 'FALSE|%s|CachyOS BC-250 kernel|%s|Active\n' "$BC250_GUI_OK" "$kernel"; else printf 'FALSE|%s|CachyOS BC-250 kernel|%s|Recommended kernel not active\n' "$BC250_GUI_WARN" "$kernel"; fi
  if [ "$cores" -ge 8 ] 2>/dev/null && [ "$threads" -ge 16 ] 2>/dev/null; then printf 'FALSE|%s|CPU topology|%sC / %sT|All cores enabled\n' "$BC250_GUI_OK" "$cores" "$threads"; else printf 'FALSE|%s|CPU topology|%sC / %sT|Expected 8C / 16T\n' "$BC250_GUI_WARN" "$cores" "$threads"; fi
  if command -v cpupower >/dev/null 2>&1; then printf 'FALSE|%s|cpupower|Installed|Available\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|cpupower|Missing|Install dependency\n' "$BC250_GUI_WARN"; fi
  if command -v vulkaninfo >/dev/null 2>&1; then printf 'FALSE|%s|Vulkan tools|Installed|Available\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Vulkan tools|Missing|Install dependency\n' "$BC250_GUI_WARN"; fi
  if [ -x /usr/bin/cyan-skillfish-governor-smu ]; then printf 'FALSE|%s|Cyan-Skillfish governor|Installed|Binary present\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Cyan-Skillfish governor|Missing|Setup required\n' "$BC250_GUI_WARN"; fi
  if [ -f /etc/cyan-skillfish-governor-smu/config.toml ]; then printf 'FALSE|%s|Cyan-Skillfish configuration|Present|Configured\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|Cyan-Skillfish configuration|Missing|Setup required\n' "$BC250_GUI_WARN"; fi
  if bc250_governor_ok; then printf 'FALSE|%s|GPU governor service|Active|Running\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU governor service|Inactive|Inspect / configure\n' "$BC250_GUI_WARN"; fi
  if bc250_telemetry_ok; then printf 'FALSE|%s|GPU telemetry|Available|Interfaces ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU telemetry|Incomplete|Inspect hardware interfaces\n' "$BC250_GUI_WARN"; fi
  if [[ "$card" == card* ]] && [ -r "/sys/class/drm/$card/device/pp_dpm_sclk" ]; then printf 'FALSE|%s|GPU DPM|Available|SCLK interface ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|GPU DPM|Unavailable|Interface missing\n' "$BC250_GUI_WARN"; fi
  if [[ "$card" == card* ]] && [ -r "/sys/class/drm/$card/device/mem_info_vram_total" ]; then printf 'FALSE|%s|VRAM telemetry|Available|Interface ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|VRAM telemetry|Unavailable|Interface missing\n' "$BC250_GUI_WARN"; fi
  if [ -x /usr/local/bin/bc250-cu-live-manager ]; then printf 'FALSE|%s|CU / WGP manager|Installed|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|CU / WGP manager|Missing|Install manager\n' "$BC250_GUI_WARN"; fi
  if bc250_umr_present; then printf 'FALSE|%s|UMR|Available|Ready\n' "$BC250_GUI_OK"; else printf 'FALSE|%s|UMR|Missing|Install diagnostic dependency\n' "$BC250_GUI_WARN"; fi
}

bc250_gui_preflight_fix() {
  local component="$1"
  case "$component" in
    BIOS) bc250_bios_setup_menu_action;;
    'CachyOS BC-250 kernel') bc250_kernel_setup_menu_action;;
    'CU / WGP manager') bc250_cu_setup_menu_action;;
    UMR) bc250_umr_setup_menu_action;;
    'GPU governor service'|'Cyan-Skillfish governor'|'Cyan-Skillfish configuration') bc250_gui_run_function 'GPU Governor / Setup Status' ui_gpu_status;;
    cpupower|Vulkan\ tools) bc250_gui_info 'Dependency' "This dependency is not installed by the current platform setup backend.\n\nUse your normal CachyOS package manager to install it, then press Refresh.";;
    *) bc250_gui_info 'Diagnostic' "No automatic installer is associated with '$component'.\n\nThe GUI will not invent a new backend action.";;
  esac
}

bc250_gui_preflight() {
  while true; do
    local rows choice rc component
    rows=$(bc250_gui_preflight_rows)
    choice=$(printf '%s' "$rows" | yad --list --radiolist --markup \
      --title="$BC250_GUI_TITLE — Preflight" --width=920 --height=620 \
      --text='<b>PLATFORM PREFLIGHT</b>    Validate the complete BC-250 environment before making changes.\n<span foreground="#70d890">● OK</span> everything required is ready    <span foreground="#f0c75e">● ACTION REQUIRED</span> something needs attention' \
      --column='' --column='Status' --column='Component' --column='Current state' --column='Result' \
      --print-column=3 --button='Fix Selected:10' --button='Refresh:11' --button='Close:0' 2>/dev/null)
    rc=$?
    [ "$rc" -eq 10 ] || { [ "$rc" -eq 11 ] && continue; return 0; }
    component="$choice"
    [ -n "$component" ] || continue
    bc250_gui_preflight_fix "$component"
  done
}

bc250_gui_platform() {
  while true; do
    local rows choice rc component bios_state kernel_state gov_state cu_state umr_state
    bc250_bios_ok && bios_state='OK — P3.00 active' || bios_state='ACTION REQUIRED — P3.00 recommended'
    bc250_kernel_ok && kernel_state="OK — $(uname -r)" || kernel_state="ACTION REQUIRED — install linux-cachyos-bc250"
    bc250_governor_ok && gov_state='OK — service active' || gov_state='ACTION REQUIRED — governor inactive'
    [ -x /usr/local/bin/bc250-cu-live-manager ] && cu_state='OK — installed' || cu_state='ACTION REQUIRED — manager missing'
    bc250_umr_present && umr_state='OK — available' || umr_state='ACTION REQUIRED — UMR missing'
    rows=$(printf '%s\n' \
      "TRUE|$BC250_GUI_OK|BIOS|$bios_state|Firmware is checked, never flashed by the toolkit" \
      "FALSE|$BC250_GUI_OK|CPU topology|$(bc250_cpu_cores)C / $(bc250_cpu_threads)T|8C / 16T expected" \
      "FALSE|$BC250_GUI_OK|CachyOS BC-250 Kernel|$kernel_state|Recommended kernel" \
      "FALSE|$BC250_GUI_OK|GPU Governor|$gov_state|Cyan-Skillfish SMU governor" \
      "FALSE|$BC250_GUI_OK|CU / WGP Manager|$cu_state|External compute-unit manager" \
      "FALSE|$BC250_GUI_OK|UMR|$umr_state|Register-level diagnostics")
    choice=$(printf '%s' "$rows" | yad --list --radiolist --markup \
      --title="$BC250_GUI_TITLE — Platform Setup" --width=920 --height=500 \
      --text='<b>PLATFORM SETUP</b>    Same prerequisite model as Preflight: inspect first, then fix only what is missing.' \
      --column='' --column='Status' --column='Component' --column='Current state' --column='Purpose' \
      --print-column=3 --button='Fix Selected:10' --button='Preflight:11' --button='Close:0' 2>/dev/null)
    rc=$?
    [ "$rc" -eq 10 ] && component="$choice" || component=''
    case "$rc" in
      10)
        case "$component" in
          BIOS) bc250_bios_setup_menu_action;;
          CachyOS\ BC-250\ Kernel) bc250_kernel_setup_menu_action;;
          GPU\ Governor) bc250_gui_run_function 'GPU Governor / Status' ui_gpu_status;;
          CU\ /\ WGP\ Manager) bc250_cu_setup_menu_action;;
          UMR) bc250_umr_setup_menu_action;;
          CPU\ topology) bc250_gui_info 'CPU Topology' "Detected: $(bc250_cpu_cores)C / $(bc250_cpu_threads)T\n\nCore unlocking is performed by BIOS, not by this GUI.";;
        esac
        ;;
      11) bc250_gui_preflight;;
      *) return 0;;
    esac
  done
}

bc250_gui_performance() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Performance Lab" \
      --width=850 --height=520 \
      --text='<b>PERFORMANCE LAB</b>    GPU OC/UV is delegated to the validated Cyan-Skillfish backend. Experimental profiles are explicitly marked.' \
      --column='' --column='Action' --column='Operating point' --column='Role' \
      TRUE 'GPU Status' 'Live state' 'Telemetry + governor + OC/UV' \
      FALSE 'Stock' '1850 MHz @ 930 mV' 'Safe baseline' \
      FALSE 'Balanced' '2000 MHz @ 1000 mV' 'Validated profile' \
      FALSE 'Aggressive' '2100 MHz @ 1025 mV' '<span foreground="#f0c75e"><b>EXPERIMENTAL</b></span>' \
      FALSE 'Maximum Experimental' '2200 MHz @ 1050 mV' '<span foreground="#f0c75e"><b>EXPERIMENTAL</b></span>' \
      FALSE 'Custom' 'Frequency / voltage / minimum frequency' 'Manual — backend validated' \
      FALSE 'Reset GPU OC/UV' 'Restore saved configuration' 'Recovery' \
      FALSE 'CPU Performance' 'No changes' 'Validation / research only' \
      --print-column=2 --button='Select:10' --button='Close:0' 2>/dev/null)
    rc=$?
    [ "$rc" -eq 10 ] || return 0
    case "$choice" in
      'GPU Status') bc250_gui_run_function 'GPU Status' ui_gpu_status;;
      'Stock') bc250_gui_confirm_function 'Apply Stock GPU Profile' 'Apply Stock: 1850 MHz @ 930 mV?' ui_require_root gpu oc apply stock;;
      'Balanced') bc250_gui_confirm_function 'Apply Balanced GPU Profile' 'Apply Balanced: 2000 MHz @ 1000 mV?' ui_require_root gpu oc apply balanced;;
      'Aggressive') bc250_gui_confirm_function 'Experimental GPU Profile' 'Apply Aggressive: 2100 MHz @ 1025 mV?\n\nThis profile is explicitly experimental.' ui_require_root gpu oc apply aggressive;;
      'Maximum Experimental') bc250_gui_confirm_function 'Experimental GPU Profile' 'Apply Maximum Experimental: 2200 MHz @ 1050 mV?\n\nThis profile is explicitly experimental.' ui_require_root gpu oc apply maximum-experimental;;
      'Custom')
        local values freq volt minimum
        values=$(yad --form --title='Custom GPU OC/UV' --width=600 \
          --text='<b>Custom operating point</b>\nThe existing backend performs the actual validation and application.' \
          --field='Maximum GPU frequency (MHz):NUM' '2000!600..2400!1' \
          --field='Voltage (mV):NUM' '1000!800..1200!1' \
          --field='Minimum GPU frequency (MHz):NUM' '600!300..2200!1' \
          --separator='|' --button='Cancel:1' --button='Continue:0' 2>/dev/null) || continue
        IFS='|' read -r freq volt minimum _ <<< "$values"
        freq=${freq%.*}; volt=${volt%.*}; minimum=${minimum%.*}
        bc250_gui_confirm_function 'Apply Custom GPU OC/UV' "Apply ${freq} MHz @ ${volt} mV (minimum ${minimum} MHz)?" ui_require_root gpu oc manual "$freq" "$volt" "$minimum"
        ;;
      'Reset GPU OC/UV') bc250_gui_confirm_function 'Reset GPU OC/UV' 'Restore the saved GPU configuration?' ui_require_root gpu oc reset;;
      'CPU Performance') bc250_gui_info 'CPU Performance' 'CPU tuning remains validation-only.\n\nNo CPU settings are changed by this GUI.';;
    esac
  done
}

bc250_gui_live_snapshot() {
  while true; do
    local card h vr load result cpu_freq cpu_temp cores threads gpu_sclk gpu_busy gpu_temp gpu_mclk vr_used vr_total vrm_temp
    card=$(bc250_gpu_card 2>/dev/null || true)
    [[ "$card" == card* ]] || { bc250_gui_error 'BC-250 GPU not detected.'; return 1; }
    h=$(bc250_hwmon "$card" 2>/dev/null || true); vr=$(bc250_gpu_vram "$card"); load=$(ui_cpu_load_percent)
    cpu_freq=$(bc250_cpu_freq); cpu_temp=$(bc250_cpu_temp); cores=$(bc250_cpu_cores); threads=$(bc250_cpu_threads)
    gpu_sclk=$(bc250_gpu_sclk "$h"); gpu_busy=$(bc250_gpu_busy "$card"); gpu_temp=$(bc250_gpu_temp "$h"); gpu_mclk=$(bc250_gpu_mclk "$h")
    vr_used=${vr% *}; vr_total=${vr#* }; vrm_temp=$(bc250_vrm_temp)
    yad --form --title="$BC250_GUI_TITLE — Live Telemetry" --width=760 --height=500 --columns=2 \
      --text='<b>LIVE TELEMETRY</b>    Read-only hardware snapshot. Refresh to sample again.' \
      --field='CPU load:RO' "${load} %" --field='CPU frequency:RO' "${cpu_freq} MHz" \
      --field='CPU temperature:RO' "${cpu_temp} °C" --field='CPU topology:RO' "${cores}C / ${threads}T" \
      --field='GPU device:RO' "$card" --field='GPU SCLK:RO' "${gpu_sclk} MHz" \
      --field='GPU load:RO' "${gpu_busy} %" --field='GPU temperature:RO' "${gpu_temp} °C" \
      --field='GPU MCLK:RO' "${gpu_mclk} MHz" --field='VRAM usage:RO' "${vr_used} / ${vr_total} MB" \
      --field='VRM temperature:RO' "${vrm_temp} °C" \
      --button='Refresh:10' --button='Close:0' 2>/dev/null
    result=$?; [ "$result" -eq 10 ] || return 0
  done
}

bc250_gui_memory() {
  local mem total avail vused vtotal used rec
  mem=$(bc250_memory_status); read -r total avail vused vtotal <<< "$mem"; used=$((total-avail))
  rec=$(bc250_memory_recommendations)
  yad --form --title="$BC250_GUI_TITLE — Memory / UMA" --width=760 --height=470 --columns=2 \
    --text='<b>MEMORY / UMA</b>    Informational view. BIOS controls the UMA split; the toolkit does not alter it here.' \
    --field='System RAM total:RO' "${total} MB" --field='System RAM used:RO' "${used} MB" \
    --field='System RAM available:RO' "${avail} MB" --field='VRAM used:RO' "${vused} MB" \
    --field='VRAM total:RO' "${vtotal} MB" --field='Workload recommendations:TXT' "$rec" \
    --button='Close:0' 2>/dev/null || true
}

bc250_gui_cpu_diagnostics() {
  local load; load=$(ui_cpu_load_percent)
  yad --form --title="$BC250_GUI_TITLE — CPU Diagnostics" --width=720 --height=440 --columns=2 \
    --text='<b>CPU DIAGNOSTICS</b>    Read-only topology, frequency, governor and thermal data.' \
    --field='Cores / Threads:RO' "$(bc250_cpu_cores)C / $(bc250_cpu_threads)T" \
    --field='Driver:RO' "$(bc250_cpu_driver)" --field='Governor:RO' "$(bc250_cpu_governor)" \
    --field='Current frequency:RO' "$(bc250_cpu_freq) MHz" --field='Load:RO' "${load} %" \
    --field='Temperature:RO' "$(bc250_cpu_temp) °C" --button='Close:0' 2>/dev/null || true
}

bc250_gui_hardware() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Hardware & Telemetry" \
      --width=850 --height=450 --text='<b>HARDWARE & TELEMETRY</b>    Measurements and diagnostics only.' \
      --column='' --column='View' --column='Description' \
      TRUE 'Live System Snapshot' 'CPU / GPU / VRM / VRAM live measurements' \
      FALSE 'Memory / UMA' 'RAM / VRAM usage and workload guidance' \
      FALSE 'CU / WGP' 'Compute-unit state and UMR diagnostics' \
      FALSE 'CPU Diagnostics' 'Topology, driver, governor, load and thermals' \
      --print-column=2 --button='Open:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
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
    local zswap zram swap_state conf rdseed mitigations choice rc
    zswap=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo N)
    [ -e /dev/zram0 ] && zram='Active' || zram='Inactive'
    if swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | awk '$2 == "file" {found=1} END{exit !found}'; then swap_state='Enabled'; else swap_state='Not configured'; fi
    conf=$(bc250_boot_conf 2>/dev/null || echo 'Not found')
    rdseed='Default'; mitigations='Default'
    [ -f "$conf" ] && grep -q 'loglevel=0' "$conf" 2>/dev/null && rdseed='Hidden'
    [ -f "$conf" ] && grep -q 'mitigations=off' "$conf" 2>/dev/null && mitigations='DISABLED'

    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — System Extras" \
      --width=900 --height=560 \
      --text="<b>SYSTEM EXTRAS</b>\n\n<b>ACTIVE / CURRENT</b>\nSwap: ${swap_state}    •    ZRAM: ${zram}    •    ZSWAP: $([ "$zswap" = Y ] && echo Enabled || echo Disabled)\nBoot: ${conf}\nRDSEED warning: ${rdseed}    •    CPU mitigations: ${mitigations}\n\n<b>ACTIONS / CHANGES</b>\nSelect an action below to apply a system change or inspect the detailed canonical status." \
      --column='' --column='Action' --column='What it does' \
      TRUE 'Show Detailed Status' 'Read-only current state' \
      FALSE 'Enable Swap' 'Create / enable persistent 16G swapfile' \
      FALSE 'Enable ZSWAP' 'Disable systemd ZRAM and enable compressed swap' \
      FALSE 'Hide RDSEED Warning' 'Set boot loglevel=0' \
      FALSE 'Disable CPU Mitigations' 'Add mitigations=off to boot configuration' \
      FALSE 'CU / WGP + UMR' 'Open compute-unit diagnostics' \
      --print-column=2 --button='Apply / Open:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
    case "$choice" in
      'Show Detailed Status') bc250_gui_run_function 'System Extras — Current State' ui_extras_status;;
      'Enable Swap') bc250_gui_confirm_function 'Enable Swap' 'Enable the persistent 16G swapfile?' ui_require_root extras swap enable 16G;;
      'Enable ZSWAP') bc250_gui_confirm_function 'Enable ZSWAP' 'Enable ZSWAP and disable systemd ZRAM?\n\nA reboot may be required.' ui_require_root extras zswap enable;;
      'Hide RDSEED Warning') bc250_gui_confirm_function 'Hide RDSEED Warning' 'Set boot loglevel=0 to hide the RDSEED warning?' ui_require_root extras rdseed hide;;
      'Disable CPU Mitigations') bc250_gui_confirm_function 'Disable CPU Mitigations' 'Add mitigations=off to the boot configuration?\n\nThis reduces security protections.' ui_require_root extras mitigations off;;
      'CU / WGP + UMR') bc250_gui_run_function 'CU / WGP + UMR' bc250_cu_status;;
    esac
  done
}

bc250_gui_restore_boot() {
  yad --question --title='Restore Boot Configuration' --width=620 \
    --text='Restore /etc/default/limine from /etc/default/limine.orig when available?' \
    --button='Cancel:1' --button='Restore:0' 2>/dev/null || return 1
  local output rc
  output=$(sudo bash -c 'if [ -f /etc/default/limine.orig ]; then cp -a /etc/default/limine.orig /etc/default/limine; command -v limine-update >/dev/null 2>&1 && limine-update || true; echo "Boot configuration restored."; else echo "No boot configuration backup found."; exit 2; fi' 2>&1)
  rc=$?; bc250_gui_text 'Restore Boot Configuration' "$output"; return "$rc"
}

bc250_gui_recovery() {
  while true; do
    local choice rc
    choice=$(yad --list --radiolist --markup --title="$BC250_GUI_TITLE — Recovery & Revert" \
      --width=820 --height=440 --text='<b>RECOVERY & REVERT</b>    Roll back only supported, reversible toolkit changes.' \
      --column='' --column='Action' --column='Description' \
      TRUE 'Reset GPU OC/UV' 'Restore saved GPU configuration' \
      FALSE 'Restore Boot Configuration' 'Restore toolkit boot backup when available' \
      FALSE 'Show System Status' 'Inspect current state before reverting' \
      --print-column=2 --button='Apply:10' --button='Close:0' 2>/dev/null)
    rc=$?; [ "$rc" -eq 10 ] || return 0
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
