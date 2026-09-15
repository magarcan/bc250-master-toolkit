#!/usr/bin/env bash

# BC-250 GPU governor platform contract.
# The toolkit supports the MastaG BC-250 kernel as its only GPU governor
# backend. Cyan-Skillfish remains the userspace governor service, but GPU
# usage/frequency reporting and frequency writes are delegated to the kernel.

bc250_gpu_governor_kernel_backend_ok() {
  local cfg="${GPU_OC_CONFIG:-/etc/cyan-skillfish-governor-smu/config.toml}"
  [ -r "$cfg" ] || return 1

  # Keep this health check dependency-free. The configuration is root-owned,
  # so it is intentionally used only from privileged setup/verification paths.
  local fix_metrics fix_freq method set_method
  fix_metrics=$(awk '
    /^\[gpu-usage\]$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^[[:space:]]*fix-metrics[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); print; exit
    }
  ' "$cfg" 2>/dev/null)
  fix_freq=$(awk '
    /^\[gpu-usage\]$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^[[:space:]]*fix-freq[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); print; exit
    }
  ' "$cfg" 2>/dev/null)
  method=$(awk '
    /^\[gpu-usage\]$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^[[:space:]]*method[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); print; exit
    }
  ' "$cfg" 2>/dev/null)
  set_method=$(awk '
    /^\[gpu\]$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^[[:space:]]*set-method[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, ""); print; exit
    }
  ' "$cfg" 2>/dev/null)

  [ "$fix_metrics" = 'false' ] || return 1
  [ "$fix_freq" = 'false' ] || return 1
  [ "$method" = '"kernel"' ] || return 1
  [ "$set_method" = '"kernel"' ] || return 1
}

bc250_gpu_governor_backend_status() {
  local cfg="${GPU_OC_CONFIG:-/etc/cyan-skillfish-governor-smu/config.toml}"
  if bc250_gpu_governor_kernel_backend_ok; then
    ok 'GPU governor backend: MastaG kernel-native configuration'
  elif [ -r "$cfg" ]; then
    warn 'GPU governor backend: incompatible with the supported MastaG kernel configuration'
    printf '  Required: [gpu-usage] fix-metrics=false, fix-freq=false, method="kernel"; [gpu] set-method="kernel"\n'
    return 1
  else
    warn "GPU governor configuration missing: $cfg"
    return 1
  fi
}

bc250_gpu_governor_ensure_kernel_backend() {
  [ "$EUID" -eq 0 ] || { die 'GPU governor configuration requires root privileges.'; return 1; }
  local cfg="${GPU_OC_CONFIG:-/etc/cyan-skillfish-governor-smu/config.toml}"
  local state_dir="${GPU_OC_STATE_DIR:-/etc/bc250-master-toolkit}"
  local backup="$state_dir/cyan-skillfish-governor-smu.config.toml.base"
  local service="${CYAN_SERVICE:-cyan-skillfish-governor-smu.service}"
  [ -f "$cfg" ] || { die "Cyan-Skillfish configuration not found: $cfg"; return 1; }

  if bc250_gpu_governor_kernel_backend_ok; then
    ok 'GPU governor already uses the MastaG kernel-native backend.'
    systemctl is-active --quiet "$service" || systemctl restart "$service" || {
      die 'Cyan-Skillfish governor could not be activated.'
      return 1
    }
    return 0
  fi

  mkdir -p "$state_dir" || return 1
  [ -f "$backup" ] || cp -a "$cfg" "$backup" || {
    die 'Could not create governor configuration backup.'
    return 1
  }

  local tmp
  tmp=$(mktemp) || {
    die 'Could not create temporary governor configuration.'
    return 1
  }

  awk '
    BEGIN { skip=0 }
    /^\[gpu-usage\]$/ {
      print "[gpu-usage]"
      print "fix-metrics = false"
      print "fix-freq = false"
      print "method = \"kernel\""
      print ""
      skip=1
      next
    }
    /^\[gpu\]$/ {
      print "[gpu]"
      print "set-method = \"kernel\""
      print ""
      skip=1
      next
    }
    /^\[/ {
      skip=0
    }
    skip { next }
    { print }
  ' "$cfg" > "$tmp"

  if ! grep -q '^\[gpu-usage\]$' "$tmp" || \
     ! grep -q '^fix-metrics = false$' "$tmp" || \
     ! grep -q '^fix-freq = false$' "$tmp" || \
     ! grep -q '^method = "kernel"$' "$tmp" || \
     ! grep -q '^\[gpu\]$' "$tmp" || \
     ! grep -q '^set-method = "kernel"$' "$tmp"; then
    rm -f "$tmp"
    die 'Generated governor configuration failed backend validation.'
    return 1
  fi

  mv "$tmp" "$cfg" || {
    rm -f "$tmp"
    die 'Could not install the corrected governor configuration.'
    return 1
  }

  systemctl restart "$service" || {
    die 'Cyan-Skillfish governor failed to restart after backend correction.'
    return 1
  }

  bc250_gpu_governor_kernel_backend_ok || {
    die 'Governor backend verification failed after correction.'
    return 1
  }
  ok 'GPU governor configured for the MastaG kernel-native backend.'
}

# Keep every GPU OC write inside the supported platform contract.
if declare -F bc250_gpu_oc_write >/dev/null 2>&1; then
  eval "$(declare -f bc250_gpu_oc_write | sed '1s/^bc250_gpu_oc_write /bc250_gpu_oc_write_original /')"
  bc250_gpu_oc_write() {
    bc250_gpu_oc_write_original "$@" || return 1
    bc250_gpu_governor_ensure_kernel_backend || return 1
  }
fi

if declare -F bc250_gpu_oc_service_verify >/dev/null 2>&1; then
  eval "$(declare -f bc250_gpu_oc_service_verify | sed '1s/^bc250_gpu_oc_service_verify /bc250_gpu_oc_service_verify_original /')"
  bc250_gpu_oc_service_verify() {
    bc250_gpu_oc_service_verify_original "$@" || return 1
    bc250_gpu_governor_kernel_backend_ok || {
      die 'Governor backend is not the required MastaG kernel-native configuration.'
      return 1
    }
  }
fi

if declare -F bc250_gpu_oc_reset >/dev/null 2>&1; then
  eval "$(declare -f bc250_gpu_oc_reset | sed '1s/^bc250_gpu_oc_reset /bc250_gpu_oc_reset_original /')"
  bc250_gpu_oc_reset() {
    bc250_gpu_oc_reset_original "$@" || return 1
    bc250_gpu_governor_ensure_kernel_backend || return 1
  }
fi

# Do not wrap the unprivileged governor service health check here. The
# Cyan-Skillfish configuration is root-owned; backend validation belongs to
# privileged setup/verification paths, while Preflight must be able to check
# service health directly as the invoking user.

# Entering Platform Setup reconciles an existing governor configuration with
# the supported kernel backend. It never flashes BIOS or changes the kernel.
if declare -F ui_platform >/dev/null 2>&1; then
  eval "$(declare -f ui_platform | sed '1s/^ui_platform /ui_platform_original /')"
  ui_platform() {
    if [ "$EUID" -eq 0 ]; then
      bc250_gpu_governor_ensure_kernel_backend || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo "$ROOT/bc250-master-toolkit" __root gpu-governor-ensure >/dev/null 2>&1 || true
    fi
    ui_platform_original
  }
fi