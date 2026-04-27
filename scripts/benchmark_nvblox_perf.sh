#!/usr/bin/env bash
# Measure ROS 2 topic throughput (Hz) + optional GPU samples while nvblox / RealSense stack runs.
# Use this to see whether depth/color/pose inputs and nvblox outputs keep up with "real time".
#
# Prerequisites (on host or inside Isaac dev container, same shell you use for ros2 launch):
#   source /opt/ros/humble/setup.bash
#   source ~/isaac_ros_ws/install/setup.bash   # or your colcon install path
#   ros2 daemon start   # optional; speeds first ros2 calls
#
# Run WHILE the stack is live, e.g. in another terminal:
#   ros2 launch nvblox_examples_bringup realsense_example.launch.py
# or with a rosbag as in NVIDIA tutorials.
#
# Usage:
#   ./scripts/benchmark_nvblox_perf.sh
#   ./scripts/benchmark_nvblox_perf.sh -d 60 -o ~/bench/run1
#   ./scripts/benchmark_nvblox_perf.sh --discover -d 45
#   NVBLOX_BENCH_TOPICS="/foo /bar" ./scripts/benchmark_nvblox_perf.sh -d 20
#
# Env:
#   NVBLOX_BENCH_DURATION   seconds (default 30) if -d not passed
#   NVBLOX_BENCH_OUT        output directory (default: ./nvblox_bench_<timestamp>)
#   NVBLOX_BENCH_TOPICS     space-separated topics (overrides built-in defaults)
#   NVBLOX_BENCH_GPU        if 0, skip nvidia-smi sampling
#   NVBLOX_BENCH_DISCOVER   if 1, merge in topics from `ros2 topic list` (camera0|nvblox|visual_slam)
#
# Defaults target Isaac ROS nvblox **release-3.2** + `realsense_example.launch.py` (static mode,
# splitter on camera0). If your graph uses different names, pass topics explicitly or --discover.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DURATION="${NVBLOX_BENCH_DURATION:-30}"
OUTDIR="${NVBLOX_BENCH_OUT:-}"
GPU_SAMPLE="${NVBLOX_BENCH_GPU:-1}"
DISCOVER="${NVBLOX_BENCH_DISCOVER:-0}"
EXTRA_TOPICS=()

usage() {
  echo "Usage: $0 [-d seconds] [-o outdir] [--discover] [--no-gpu] [extra_topic ...]" >&2
  echo "See header in script for ROS setup and env vars." >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -d)
      DURATION="$2"
      shift 2
      ;;
    -o)
      OUTDIR="$2"
      shift 2
      ;;
    --discover)
      DISCOVER=1
      shift
      ;;
    --no-gpu)
      GPU_SAMPLE=0
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      EXTRA_TOPICS+=("$1")
      shift
      ;;
  esac
done

if ! command -v ros2 &>/dev/null; then
  echo "ros2 not found. Source ROS + workspace install first, e.g.:" >&2
  echo "  source /opt/ros/humble/setup.bash && source ~/isaac_ros_ws/install/setup.bash" >&2
  exit 1
fi

# release-3.2 realsense_example: splitter depth + color + infra to VSLAM; VSLAM pose; nvblox mesh.
DEFAULT_TOPICS=(
  /camera0/realsense_splitter_node/output/depth
  /camera0/color/image_raw
  /camera0/realsense_splitter_node/output/infra_1
  /visual_slam/tracking/vo_pose
  /nvblox_node/mesh
)

topics=()
if [[ -n "${NVBLOX_BENCH_TOPICS:-}" ]]; then
  # shellcheck disable=SC2206
  topics=( ${NVBLOX_BENCH_TOPICS} )
else
  topics=( "${DEFAULT_TOPICS[@]}" )
fi
topics+=("${EXTRA_TOPICS[@]}")

if [[ "$DISCOVER" == "1" ]]; then
  # Typical names: /camera0/..., /nvblox_node/..., /visual_slam/...
  mapfile -t _disc < <(ros2 topic list 2>/dev/null | grep -E '^/(camera0|nvblox_node|visual_slam)/' || true)
  for t in "${_disc[@]}"; do
    topics+=("$t")
  done
fi

# De-duplicate while preserving order
declare -A seen=()
uniq_topics=()
for t in "${topics[@]}"; do
  [[ -z "$t" ]] && continue
  if [[ -z "${seen[$t]:-}" ]]; then
    seen[$t]=1
    uniq_topics+=("$t")
  fi
done
topics=( "${uniq_topics[@]}" )

if [[ ${#topics[@]} -eq 0 ]]; then
  echo "No topics to measure." >&2
  exit 1
fi

if [[ -z "$OUTDIR" ]]; then
  OUTDIR="${ROOT_DIR}/nvblox_bench_$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$OUTDIR"

HOST="$(hostname)"
ROS_DISTRO="${ROS_DISTRO:-unknown}"
{
  echo "host=${HOST}"
  echo "date=$(date -Is)"
  echo "ros_distro=${ROS_DISTRO}"
  echo "duration_s=${DURATION}"
  echo "topics=${topics[*]}"
} | tee "${OUTDIR}/meta.txt"

ros2 topic list > "${OUTDIR}/ros2_topic_list.txt" 2>&1 || true

# --- GPU sampling (1 Hz) ---
gpu_pid=""
if [[ "$GPU_SAMPLE" != "0" ]] && command -v nvidia-smi &>/dev/null; then
  (
    while true; do
      ts="$(date +%s)"
      nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total \
        --format=csv,noheader 2>/dev/null | sed "s/^/${ts},/" || true
      sleep 1
    done
  ) > "${OUTDIR}/gpu_samples.csv" &
  gpu_pid=$!
  echo "gpu_csv=${OUTDIR}/gpu_samples.csv" >> "${OUTDIR}/meta.txt"
else
  echo "gpu_sampling=skipped" >> "${OUTDIR}/meta.txt"
fi

cleanup() {
  if [[ -n "${gpu_pid}" ]] && kill -0 "${gpu_pid}" 2>/dev/null; then
    kill "${gpu_pid}" 2>/dev/null || true
    wait "${gpu_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Measuring for ${DURATION}s → ${OUTDIR}"
echo "Topics (${#topics[@]}):"
printf '  %s\n' "${topics[@]}"

pids=()
for t in "${topics[@]}"; do
  safe="$(echo "$t" | sed 's/[^A-Za-z0-9._-]/_/g')"
  out="${OUTDIR}/hz_${safe}.txt"
  if ! ros2 topic type "$t" &>/dev/null; then
    echo "Topic not available (skip): $t" | tee "$out"
    continue
  fi
  echo "Starting hz: $t"
  (
    set +e
    echo "topic=$t" >"$out"
    ros2 topic type "$t" >>"$out" 2>&1 || true
    echo "--- ros2 topic hz (${DURATION}s) ---" >>"$out"
    timeout --signal=INT "${DURATION}" ros2 topic hz "$t" >>"$out" 2>&1
    echo "--- exit: $? ---" >>"$out"
  ) &
  pids+=("$!")
done

for pid in "${pids[@]:-}"; do
  wait "$pid" || true
done

# --- Summary: parse "average rate" lines from hz logs ---
SUMMARY="${OUTDIR}/summary.txt"
{
  echo "=== nvblox / stack throughput summary ==="
  echo "host=${HOST}  date=$(date -Is)  duration_s=${DURATION}"
  echo
  echo "Interpretation:"
  echo "  - Input depth/color near camera nominal FPS → sensor + splitter keep up."
  echo "  - vo_pose Hz → VSLAM output rate (often tracks stereo/IMU rate)."
  echo "  - nvblox mesh (or other nvblox outputs) often << depth Hz; that is normal (decimated visualization)."
  echo "  - If depth average rate << expected camera FPS under load, pipeline is not real-time."
  echo
  for f in "${OUTDIR}"/hz_*.txt; do
    [[ -f "$f" ]] || continue
    echo "--- $(basename "$f") ---"
    grep -E "^topic=|^Type:|average rate:|min:.*max:.*std dev" "$f" | tail -20 || true
    echo
  done
} | tee "$SUMMARY"

uptime | tee -a "${OUTDIR}/meta.txt"
echo "Done. Open: ${SUMMARY}"
