#!/usr/bin/env bash
# DGX Spark is aarch64 but not Jetson: isaac_ros_common release-3.2 run_dev.sh assumes Jetson and
# sets NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all plus Tegra bind mounts.
# That fails with: unresolvable CDI devices nvidia.com/pva=all
#
# Spark may ship /usr/lib/aarch64-linux-gnu/tegra, so we must not key off that directory alone.
# Jetson images ship /etc/nv_tegra_release; Spark does not — use that to gate the Jetson block.
#
# Usage:
#   ./scripts/patch_isaac_run_dev_spark.sh
#   ./scripts/patch_isaac_run_dev_spark.sh /path/to/isaac_ros_common/scripts/run_dev.sh
#
# See docs/ISAAC_ROS_NVBLOX_DGX.md
set -euo pipefail

RUN_DEV="${1:-${HOME}/isaac_ros_ws/src/isaac_ros_common/scripts/run_dev.sh}"

if [[ ! -f "${RUN_DEV}" ]]; then
  echo "run_dev.sh not found: ${RUN_DEV}" >&2
  exit 1
fi

if grep -Fq 'if [[ $PLATFORM == "aarch64" ]] && [[ -f /etc/nv_tegra_release ]]; then' "${RUN_DEV}"; then
  echo "Already patched (Jetson guard uses nv_tegra_release): ${RUN_DEV}"
  exit 0
fi

# Upgrade older sandbox patch that used the tegra directory (exists on Spark too).
if grep -Fq 'if [[ $PLATFORM == "aarch64" ]] && [[ -d /usr/lib/aarch64-linux-gnu/tegra ]]; then' "${RUN_DEV}"; then
  cp -a "${RUN_DEV}" "${RUN_DEV}.bak.spark-$(date +%Y%m%d%H%M%S)"
  sed -i 's/if \[\[ \$PLATFORM == "aarch64" \]\] && \[\[ -d \/usr\/lib\/aarch64-linux-gnu\/tegra \]\]; then/if [[ $PLATFORM == "aarch64" ]] \&\& [[ -f \/etc\/nv_tegra_release ]]; then/' "${RUN_DEV}"
  echo "Patched (tegra-dir guard → nv_tegra_release): ${RUN_DEV}"
  echo "Re-run from ~/isaac_ros_ws:  ./src/isaac_ros_common/scripts/run_dev.sh"
  exit 0
fi

if ! grep -Fq 'if [[ $PLATFORM == "aarch64" ]]; then' "${RUN_DEV}"; then
  echo "Expected pattern not found; upstream run_dev.sh may have changed. Edit manually." >&2
  exit 1
fi

cp -a "${RUN_DEV}" "${RUN_DEV}.bak.spark-$(date +%Y%m%d%H%M%S)"
sed -i 's/if \[\[ \$PLATFORM == "aarch64" \]\]; then/if [[ $PLATFORM == "aarch64" ]] \&\& [[ -f \/etc\/nv_tegra_release ]]; then/' "${RUN_DEV}"

echo "Patched: ${RUN_DEV}"
echo "Backup: ${RUN_DEV}.bak.spark-*"
echo "Re-run from ~/isaac_ros_ws:  ./src/isaac_ros_common/scripts/run_dev.sh"
