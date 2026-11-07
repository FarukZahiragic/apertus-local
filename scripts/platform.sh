#!/usr/bin/env bash
# Shared macOS/Linux helpers. Compatible with the Bash 3.2 shipped by macOS.
# Source this file from scripts; execute it to print a hardware summary.
set -euo pipefail

ap_os() { uname -s; }
ap_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64) echo x86_64 ;;
    *) uname -m ;;
  esac
}
ap_jobs() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4
}
ap_threads() {
  local count=""
  if [[ "$(ap_os)" == Darwin ]]; then
    count="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu 2>/dev/null || true)"
  elif command -v lscpu >/dev/null 2>&1; then
    count="$(lscpu -p=CORE,SOCKET 2>/dev/null | awk '!/^#/ {seen[$0]=1} END {for (c in seen) n++; print n+0}')"
  fi
  case "$count" in ''|0|*[!0-9]*) count=4 ;; esac
  echo "$count"
}
ap_memory_bytes() {
  if [[ "$(ap_os)" == Darwin ]]; then
    sysctl -n hw.memsize
  else
    awk '/^MemTotal:/ {printf "%.0f\n", $2 * 1024}' /proc/meminfo
  fi
}
ap_hardware() {
  local cpu memory kind="${HARDWARE_KIND:-machine}"
  memory="$(ap_memory_bytes | awk '{printf "%.0f", $1 / 1073741824}')"
  if [[ "$(ap_os)" == Darwin ]]; then
    cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)"
    echo "${HARDWARE_KIND:-Mac}: $cpu, $memory GB, macOS $(sw_vers -productVersion)"
  else
    cpu="$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)"
    if [[ "$cpu" == *i5-1135G7* && -z "${HARDWARE_KIND:-}" ]]; then
      echo 'laptop i5-1135G7'
      return
    fi
    if [[ -z "${HARDWARE_KIND:-}" ]] && command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --vm --quiet; then
      kind='VM (NOT laptop)'
    fi
    echo "$kind: ${cpu:-$(uname -m)}, $(ap_jobs) logical CPUs, $memory GB"
  fi
}
ap_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
ap_verify() {
  [[ "$(ap_sha256 "$1")" == "$2" ]]
}
ap_device_available() {
  # Device enumeration alone does not prove that model inference is supported.
  local devices
  devices="$("$1" --list-devices 2>&1)" || return 1
  case "$2" in
    metal) [[ "$devices" =~ (Metal|MTL)[0-9]+: ]] ;;
    vulkan) [[ "$devices" =~ Vulkan[0-9]+: ]] ;;
    *) return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Hardware: $(ap_hardware)"
  echo "Platform: $(ap_os) $(ap_arch)"
  echo "Suggested CPU threads: $(ap_threads)"
fi
