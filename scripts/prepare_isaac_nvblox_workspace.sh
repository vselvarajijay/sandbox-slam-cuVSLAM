#!/usr/bin/env bash
# Optional: clone Isaac ROS repos for nvblox + visual_slam. The dev container (run_dev.sh) is
# separate from pycuvslam:realsense-cu13 in this repo. See docs/ISAAC_ROS_NVBLOX_DGX.md
set -euo pipefail

# Where to git-clone the Isaac ROS repos. Default: ~/isaac_ros_ws
# We do NOT use ISAAC_ROS_WS for this, because many shells set ISAAC_ROS_WS to a random
# path (e.g. this repo) and that hijacked the old script — clones ended up in
# <repo>/src/ while docs said ~/isaac_ros_ws. Override explicitly if needed:
#   NVBLOX_ISAAC_WS=/path/to/ws ./scripts/prepare_isaac_nvblox_workspace.sh
WS_ROOT="${NVBLOX_ISAAC_WS:-$HOME/isaac_ros_ws}"
# Same ref for all three repos. Default release-3.2: still ships scripts/run_dev.sh at repo root.
# Branch "main" (and newer release-4.x layouts) removed that path — run_dev.sh is missing → use a
# release branch that matches NVIDIA's docs for your ROS distro, or follow Isaac 4.x "isaac-ros" CLI.
ISAAC_ROS_GITREF="${ISAAC_ROS_GITREF:-release-3.2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "${WS_ROOT}"
WS_ROOT="$(cd "${WS_ROOT}" && pwd -P)"

mkdir -p "${WS_ROOT}/src"
cd "${WS_ROOT}/src"

# Replace existing clones (e.g. you were on main with no run_dev.sh): ISAAC_NVBLOX_SYNC=1 ./scripts/prepare_isaac_nvblox_workspace.sh
if [[ "${ISAAC_NVBLOX_SYNC:-}" =~ ^(1|true|yes)$ ]]; then
  echo "ISAAC_NVBLOX_SYNC: removing isaac_ros_common, isaac_ros_nvblox, isaac_ros_visual_slam under ${WS_ROOT}/src ..."
  rm -rf "${WS_ROOT}/src/isaac_ros_common" "${WS_ROOT}/src/isaac_ros_nvblox" "${WS_ROOT}/src/isaac_ros_visual_slam"
fi

clone_or_fetch() {
  local url="$1" name
  name="$(basename "$url" .git)"
  if [[ -d "${name}/.git" ]]; then
    br="$(git -C "${name}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
    echo "Already present: ${WS_ROOT}/src/${name} (git branch: ${br}; skipping — set ISAAC_NVBLOX_SYNC=1 to re-clone at ${ISAAC_ROS_GITREF})"
  else
    echo "Cloning ${name} @ ${ISAAC_ROS_GITREF} ..."
    if git clone --depth 1 --branch "${ISAAC_ROS_GITREF}" "${url}" 2>/dev/null; then
      : ok
    else
      echo "  (branch ${ISAAC_ROS_GITREF} not found, cloning default branch)"
      git clone --depth 1 "${url}"
    fi
  fi
}

clone_or_fetch "https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common.git"
clone_or_fetch "https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox.git"
clone_or_fetch "https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam.git"

COMMON="${WS_ROOT}/src/isaac_ros_common"
RUN_DEV=""
if [[ -f "${COMMON}/scripts/run_dev.sh" ]]; then
  RUN_DEV="${COMMON}/scripts/run_dev.sh"
fi

echo
echo "Workspace (Isaac colcon root): ${WS_ROOT}"
echo "  src:       ${WS_ROOT}/src"
echo "Git ref:     ${ISAAC_ROS_GITREF} (override: ISAAC_ROS_GITREF; path: NVBLOX_ISAAC_WS)"
echo
if [[ -n "${RUN_DEV}" ]]; then
  echo "Next: enter Isaac's dev image (not the pycuvslam container). Run from workspace root:"
  echo "  cd \"${WS_ROOT}\" && ./src/isaac_ros_common/scripts/run_dev.sh"
  echo "(absolute: ${RUN_DEV} — still run from \"${WS_ROOT}\" so the mount is correct)"
else
  echo "WARNING: ${COMMON}/scripts/run_dev.sh not found."
  echo "  Branch \"main\" and some release-4.x trees no longer place run_dev.sh here."
  echo "  Fix: rm -rf \"${COMMON}\" && ISAAC_ROS_GITREF=release-3.2 \"${SCRIPT_DIR}/prepare_isaac_nvblox_workspace.sh\""
  echo "  Or follow current Isaac ROS docs for your release (isaac-ros CLI / new paths)."
fi
echo "Then: rosdep, colcon build, and:"
echo "  ros2 launch nvblox_examples_bringup realsense_example.launch.py"
echo
echo "Full context: ${REPO_ROOT}/docs/ISAAC_ROS_NVBLOX_DGX.md"
