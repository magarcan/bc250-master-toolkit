#!/usr/bin/env bash

# Compatibility shim. The authoritative GPU OC status implementation lives in gpu_oc.sh.
# Do not read the protected Cyan-Skillfish config here: read-only status must work as a normal user.
bc250_gpu_oc_status_readonly() {
  bc250_gpu_oc_status "$@"
}
