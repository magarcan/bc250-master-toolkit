#!/usr/bin/env bash

GPU_OC_CONFIG=/etc/cyan-skillfish-governor-smu/config.toml
GPU_OC_STATE_DIR=/etc/bc250-master-toolkit
GPU_OC_BACKUP="$GPU_OC_STATE_DIR/cyan-skillfish-governor-smu.config.toml.base"
GPU_OC_STATE="$GPU_OC_STATE_DIR/gpu-profile"
CYAN_SERVICE="${CYAN_SERVICE:-cyan-skillfish-governor-smu.service}"

bc250_gpu_oc_profile_value() {
  local name="$1" key="$2"
  awk -v n="$name" -v k="$key" '
    $0 ~ /^name = / { cur=$0; gsub(/^name = |"/,"",cur) }
    cur==n && $0 ~ "^" k " = " { print $3; exit }
  ' "$ROOT/profiles/gpu.toml" 2>/dev/null | tr -d '"'
}

bc250_gpu_oc_profile_exists() {
  local name="$1"
  [ -n "$(bc250_gpu_oc_profile_value "$name" frequency_mhz)" ] && [ -n "$(bc250_gpu_oc_profile_value "$name" voltage_mv)" ]
}

bc250_gpu_oc_range() {
  local file="$GPU_OC_CONFIG"
  local content
  if [ -r "$file" ]; then
    content=$(cat "$file")
  elif [ -f "$file" ] && command -v sudo >/dev/null 2>&1 && content=$(sudo -n cat "$file" 2>/dev/null); then
    :
  else
    return 1
  fi
  awk '
    /^\[frequency-range\]/{inrange=1;next}
    /^\[/{inrange=0}
    inrange && /^[[:space:]]*min[[:space:]]*=/ {min=$0}
    inrange && /^[[:space:]]*max[[:space:]]*=/ {max=$0}
    END {gsub(/.*=[[:space:]]*/,"",min);gsub(/.*=[[:space:]]*/,"",max);print min "|" max}
  ' <<< "$content"
}

bc250_gpu_oc_active_profile() { [ -r "$GPU_OC_STATE" ] && cat "$GPU_OC_STATE" || echo none; }

bc250_gpu_oc_status() {
  local range min max profile
  [ -f "$GPU_OC_CONFIG" ] || { warn 'Cyan-Skillfish configuration not found.'; return 1; }
  range=$(bc250_gpu_oc_range 2>/dev/null || true)
  min=${range%%|*}; max=${range#*|}; profile=$(bc250_gpu_oc_active_profile)
  [ -n "$min" ] && [ -n "$max" ] || { warn 'Cyan-Skillfish frequency range could not be read.'; return 1; }
  printf 'GPU OC/UV control\n  Active profile        : %s\n  Governor range        : %s–%s MHz\n  Config                : %s\n' "$profile" "$min" "$max" "$GPU_OC_CONFIG"
  echo
  info 'The range is the governor operating envelope. The active profile or manual target defines the top frequency and voltage.'
}

bc250_gpu_oc_profiles() {
  banner; heading 'GPU OC profiles'
  cat "$ROOT/profiles/gpu.toml" 2>/dev/null || { warn 'GPU profile file missing.'; return 1; }
  if [ -r "$ROOT/profiles/gpu-personal.toml" ]; then echo; cat "$ROOT/profiles/gpu-personal.toml"; fi
  echo; info 'Profiles are starting points only. Applying one changes Cyan-Skillfish; no benchmark is run automatically.'
  info 'Manual: gpu oc manual <maxMHz> <mV> [minMHz]   |   Personal: gpu oc create <name> <maxMHz> <mV> [minMHz]'
}

bc250_gpu_oc_validate() {
  local freq="$1" volt="$2" min_freq="${3:-300}"
  [[ "$freq" =~ ^[0-9]+$ && "$volt" =~ ^[0-9]+$ && "$min_freq" =~ ^[0-9]+$ ]] || die 'Frequency, minimum frequency and voltage must be integer values.'
  (( freq >= 300 && freq <= 2230 )) || die 'Maximum frequency must be between 300 and 2230 MHz.'
  (( min_freq >= 300 && min_freq <= 2230 )) || die 'Minimum frequency must be between 300 and 2230 MHz.'
  (( min_freq <= freq )) || die 'Minimum frequency cannot exceed maximum frequency.'
  (( volt >= 600 && volt <= 1200 )) || die 'Voltage must be between 600 and 1200 mV.'
}

bc250_gpu_oc_write() {
  local freq="$1" volt="$2" min_freq="$3" tmp
  mkdir -p "$GPU_OC_STATE_DIR"
  [ -f "$GPU_OC_BACKUP" ] || cp -a "$GPU_OC_CONFIG" "$GPU_OC_BACKUP" || die 'Could not create governor configuration backup.'
  tmp=$(mktemp)
  python3 - "$GPU_OC_CONFIG" "$tmp" "$min_freq" "$freq" "$volt" <<'PY'
import re, sys
src,dst,minf,maxf,volt=sys.argv[1:]
s=open(src,encoding='utf-8').read()
m=re.search(r'^\[frequency-range\][\s\S]*?(?=^\[|\Z)',s,re.M)
if not m:
    s=s.rstrip()+f'\n\n[frequency-range]\nmin = {minf}\nmax = {maxf}\n'
else:
    b=m.group(0)
    b=re.sub(r'(^min\s*=\s*)\d+',r'\g<1>'+minf,b,count=1,flags=re.M)
    b=re.sub(r'(^max\s*=\s*)\d+',r'\g<1>'+maxf,b,count=1,flags=re.M)
    if not re.search(r'^min\s*=',b,re.M): b+=f'min = {minf}\n'
    if not re.search(r'^max\s*=',b,re.M): b+=f'max = {maxf}\n'
    s=s[:m.start()]+b+s[m.end():]
s=re.sub(r'\[\[safe-points\]\]\s*\nfrequency\s*=\s*'+re.escape(maxf)+r'\s*\nvoltage\s*=\s*\d+\s*\n?','',s,flags=re.M)
s=s.rstrip()+f'\n\n[[safe-points]]\nfrequency = {maxf}\nvoltage = {volt}\n'
open(dst,'w',encoding='utf-8').write(s)
PY
  mv "$tmp" "$GPU_OC_CONFIG" || die 'Could not update governor configuration.'
}

bc250_gpu_oc_apply_values() {
  need_root
  local name="$1" freq="$2" volt="$3" requested_min="${4:-}" range min_freq
  [ -f "$GPU_OC_CONFIG" ] || die "Cyan-Skillfish configuration not found: $GPU_OC_CONFIG"
  range=$(bc250_gpu_oc_range 2>/dev/null || true); min_freq=${range%%|*}; [ -n "$min_freq" ] || min_freq=1000
  [ -n "$requested_min" ] && min_freq="$requested_min"
  bc250_gpu_oc_validate "$freq" "$volt" "$min_freq"
  bc250_gpu_oc_write "$freq" "$volt" "$min_freq"
  printf '%s\n' "$name" > "$GPU_OC_STATE"
  systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart.'
  systemctl is-active --quiet "$CYAN_SERVICE" || die 'Cyan-Skillfish governor is not active after profile application.'
  ok "GPU OC/UV applied: $name — ${freq} MHz @ ${volt} mV"
  printf '  Governor range        : %s–%s MHz\n' "$min_freq" "$freq"
  info 'No benchmark was run. Validate the selected setting with your own workload.'
}

bc250_gpu_oc_apply() {
  local name="${1:-}" freq volt
  [ -n "$name" ] || die 'Use: gpu oc apply <profile>'
  bc250_gpu_oc_profile_exists "$name" || die "Unknown GPU OC profile: $name. Use: gpu oc profiles"
  freq=$(bc250_gpu_oc_profile_value "$name" frequency_mhz); volt=$(bc250_gpu_oc_profile_value "$name" voltage_mv)
  bc250_gpu_oc_apply_values "$name" "$freq" "$volt"
}

bc250_gpu_oc_manual() {
  local freq="${1:-}" volt="${2:-}" min_freq="${3:-}"
  [ -n "$freq" ] && [ -n "$volt" ] || die 'Use: gpu oc manual <maxMHz> <mV> [minMHz]'
  bc250_gpu_oc_apply_values "manual-${freq}mhz-${volt}mv" "$freq" "$volt" "$min_freq"
}

bc250_gpu_oc_create() {
  need_root
  local name="${1:-}" freq="${2:-}" volt="${3:-}" min_freq="${4:-}" file
  [ -n "$name" ] && [ -n "$freq" ] && [ -n "$volt" ] || die 'Use: gpu oc create <name> <maxMHz> <mV> [minMHz]'
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die 'Profile name may contain only letters, numbers, dot, underscore and hyphen.'
  if [ -n "$min_freq" ]; then bc250_gpu_oc_validate "$freq" "$volt" "$min_freq"; else bc250_gpu_oc_validate "$freq" "$volt" 300; fi
  file="$ROOT/profiles/gpu-personal.toml"
  if [ ! -f "$file" ]; then printf '# User-created BC-250 GPU profiles\n' > "$file"; fi
  grep -q "^name = \"$name\"$" "$file" && die "Personal profile already exists: $name"
  if [ -n "$min_freq" ]; then
    printf '\n[[profile]]\nname = "%s"\nfrequency_mhz = %s\nvoltage_mv = %s\nmin_frequency_mhz = %s\nclassification = "user"\n' "$name" "$freq" "$volt" "$min_freq" >> "$file"
  else
    printf '\n[[profile]]\nname = "%s"\nfrequency_mhz = %s\nvoltage_mv = %s\nclassification = "user"\n' "$name" "$freq" "$volt" >> "$file"
  fi
  ok "Personal GPU profile created: $name — ${freq} MHz @ ${volt} mV"
  info "Apply it with: gpu oc apply-personal $name"
}

bc250_gpu_oc_apply_personal() {
  local name="${1:-}" file="$ROOT/profiles/gpu-personal.toml" freq volt min_freq
  [ -n "$name" ] || die 'Use: gpu oc apply-personal <name>'
  [ -r "$file" ] || die 'No personal GPU profiles exist.'
  freq=$(awk -v n="$name" '$0~/^name = /{cur=$0;gsub(/^name = |"/,"",cur)} cur==n && /^frequency_mhz = /{print $3;exit}' "$file")
  volt=$(awk -v n="$name" '$0~/^name = /{cur=$0;gsub(/^name = |"/,"",cur)} cur==n && /^voltage_mv = /{print $3;exit}' "$file")
  min_freq=$(awk -v n="$name" '$0~/^name = /{cur=$0;gsub(/^name = |"/,"",cur)} cur==n && /^min_frequency_mhz = /{print $3;exit}' "$file")
  [ -n "$freq" ] && [ -n "$volt" ] || die "Unknown personal GPU profile: $name"
  bc250_gpu_oc_apply_values "$name" "$freq" "$volt" "$min_freq"
}

bc250_gpu_oc_reset() {
  need_root
  [ -f "$GPU_OC_BACKUP" ] || die 'No saved pre-profile configuration exists; nothing to reset.'
  cp -a "$GPU_OC_BACKUP" "$GPU_OC_CONFIG" || die 'Could not restore the saved Cyan-Skillfish configuration.'
  rm -f "$GPU_OC_STATE"
  systemctl restart "$CYAN_SERVICE" 2>/dev/null || die 'Cyan-Skillfish governor failed to restart after reset.'
  systemctl is-active --quiet "$CYAN_SERVICE" || die 'Cyan-Skillfish governor is not active after reset.'
  ok 'GPU OC/UV reset; original Cyan-Skillfish configuration restored.'
}
