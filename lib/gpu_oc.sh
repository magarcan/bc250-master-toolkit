#!/usr/bin/env bash

GPU_OC_CONFIG=/etc/cyan-skillfish-governor-smu/config.toml
GPU_OC_STATE_DIR=/etc/bc250-master-toolkit
GPU_OC_BACKUP="$GPU_OC_STATE_DIR/cyan-skillfish-governor-smu.config.toml.base"
GPU_OC_STATE="$GPU_OC_STATE_DIR/gpu-profile"

bc250_gpu_oc_profile_value() {
  local name="$1" key="$2"
  awk -v n="$name" -v k="$key" '
    $0 ~ /^name = / { cur=$0; gsub(/^name = |"/,"",cur) }
    cur==n && $0 ~ "^" k " = " { print $3; exit }
  ' "$ROOT/profiles/gpu.toml" 2>/dev/null | tr -d '"'
}

bc250_gpu_oc_profile_exists() {
  local name="$1"
  [ -n "$(bc250_gpu_oc_profile_value "$name" frequency_mhz)" ] && \
  [ -n "$(bc250_gpu_oc_profile_value "$name" voltage_mv)" ]
}

bc250_gpu_oc_range() {
  local f=/etc/cyan-skillfish-governor-smu/config.toml
  awk '
    /^\[frequency-range\]/{inrange=1; next}
    /^\[/{inrange=0}
    inrange && /^min[[:space:]]*=/ {min=$0}
    inrange && /^max[[:space:]]*=/ {max=$0}
    END {print min "|" max}
  ' "$f" 2>/dev/null
}

bc250_gpu_oc_active_profile() {
  [ -r "$GPU_OC_STATE" ] && cat "$GPU_OC_STATE" || echo none
}

bc250_gpu_oc_status() {
  local range min max profile
  [ -r "$GPU_OC_CONFIG" ] || { warn 'Cyan-Skillfish configuration not found.'; return 1; }
  range=$(bc250_gpu_oc_range)
  min=${range%%|*}; max=${range#*|}
  printf 'GPU OC/UV control\n'
  printf '  Active profile        : %s\n' "$(bc250_gpu_oc_active_profile)"
  printf '  Governor range        : %s / %s\n' "${min#*= }" "${max#*= }"
  printf '  Config                : %s\n' "$GPU_OC_CONFIG"
  echo
  info 'The range is the governor operating envelope. The selected profile defines its top frequency and target voltage.'
}

bc250_gpu_oc_profiles() {
  banner
  heading 'GPU OC profiles'
  cat "$ROOT/profiles/gpu.toml" 2>/dev/null || { warn 'GPU profile file missing.'; return 1; }
  echo
  info 'Profiles are starting points only. Applying a profile changes the Cyan-Skillfish governor configuration; no benchmark is run automatically.'
}

bc250_gpu_oc_apply() {
  need_root
  local name="${1:-}" freq volt range_min tmp backup
  [ -n "$name" ] || die 'Use: gpu oc apply <profile>'
  bc250_gpu_oc_profile_exists "$name" || die "Unknown GPU OC profile: $name. Use: gpu oc profiles"
  [ -f "$GPU_OC_CONFIG" ] || die "Cyan-Skillfish configuration not found: $GPU_OC_CONFIG"

  freq=$(bc250_gpu_oc_profile_value "$name" frequency_mhz)
  volt=$(bc250_gpu_oc_profile_value "$name" voltage_mv)
  range_min=$(bc250_gpu_oc_range | cut -d'|' -f1 | sed 's/.*= *//')
  [ -n "$range_min" ] || range_min=1000

  if [ ! -f "$GPU_OC_BACKUP" ]; then
    mkdir -p "$GPU_OC_STATE_DIR"
    cp -a "$GPU_OC_CONFIG" "$GPU_OC_BACKUP" || die 'Could not create governor configuration backup.'
  fi

  tmp=$(mktemp)
  python3 - "$GPU_OC_CONFIG" "$tmp" "$range_min" "$freq" "$volt" <<'PY'
import re, sys
src, dst, min_freq, max_freq, target_mv = sys.argv[1:]
s = open(src, encoding='utf-8').read()
# Keep the user's minimum governor frequency and all unrelated settings.
s, n = re.subn(r'(\[frequency-range\][\s\S]*?^min\s*=\s*)\d+', r'\g<1>' + min_freq, s, count=1, flags=re.M)
if n == 0:
    s = s.rstrip() + f'\n\n[frequency-range]\nmin = {min_freq}\nmax = {max_freq}\n'
else:
    s, n = re.subn(r'(\[frequency-range\][\s\S]*?^max\s*=\s*)\d+', r'\g<1>' + max_freq, s, count=1, flags=re.M)
    if n == 0:
        s = s.rstrip() + f'\nmax = {max_freq}\n'
# Replace an existing safe point at the target frequency; otherwise append one.
pattern = rf'(\[\[safe-points\]\]\s*\nfrequency\s*=\s*{re.escape(max_freq)}\s*\nvoltage\s*=\s*)\d+'
s, n = re.subn(pattern, r'\g<1>' + target_mv, s, count=1, flags=re.M)
if n == 0:
    s = s.rstrip() + f'\n\n[[safe-points]]\nfrequency = {max_freq}\nvoltage = {target_mv}\n'
open(dst, 'w', encoding='utf-8').write(s)
PY
  mv "$tmp" "$GPU_OC_CONFIG" || { rm -f "$tmp"; die 'Could not update governor configuration.'; }

  printf '%s\n' "$name" > "$GPU_OC_STATE"
  systemctl restart cyan-skillfish-governor-smu.service || die 'Cyan-Skillfish governor failed to restart; configuration was changed but service is not active.'
  systemctl is-active --quiet cyan-skillfish-governor-smu.service || die 'Cyan-Skillfish governor is not active after profile application.'
  ok "GPU profile applied: $name — ${freq} MHz @ ${volt} mV"
  printf '  Governor range        : %s–%s MHz\n' "$range_min" "$freq"
  info 'No benchmark was run. Validate the selected profile with your own workload.'
}

bc250_gpu_oc_reset() {
  need_root
  [ -f "$GPU_OC_BACKUP" ] || die 'No saved pre-profile configuration exists; nothing to reset.'
  cp -a "$GPU_OC_BACKUP" "$GPU_OC_CONFIG" || die 'Could not restore the saved governor configuration.'
  rm -f "$GPU_OC_STATE"
  systemctl restart cyan-skillfish-governor-smu.service || die 'Cyan-Skillfish governor failed to restart after reset.'
  systemctl is-active --quiet cyan-skillfish-governor-smu.service || die 'Cyan-Skillfish governor is not active after reset.'
  ok 'GPU OC profile reset; original Cyan-Skillfish configuration restored.'
}
