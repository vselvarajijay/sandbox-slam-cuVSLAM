#!/usr/bin/env bash
# End-to-end: ensure cuVSLAM clone, Docker image, then run KITTI in the PyCuVSLAM container.
#
# Usage (from the sandbox repo root):
#   ./scripts/run_kitti_e2e.sh
#   KITTI_SAVE_RRD=/cuvslam/examples/kitti/out.rrd ./scripts/run_kitti_e2e.sh
#   (Files appear on the host under CUVSLAM_DIR with the same path after /cuvslam/ — the script
#   prints the absolute host path; copy the .rrd to a Mac and open with: rerun your.rrd)
#   Use KITTI_SAVE_RRD=.../file.rrd — do not pass bare --save-rrd; or --save-rrd /cuvslam/.../f.rrd
#   ./scripts/run_kitti_e2e.sh --dense
#   ./scripts/run_kitti_e2e.sh --dense -- --sequence /datasets/kitti/sequences/00
# If dataset/sequences/06 is not present, this script sets KITTI_USE_SYNTHETIC_DEMO=1 when the
# bundled demo exists (synthetic). Override with KITTI_SEQUENCE=… or KITTI_USE_SYNTHETIC_DEMO=0.
#
# Options (must appear before -- if you use --):
#   --dense     Run track_kitti_dense.py (SGBM + colored points) instead of track_kitti.py
#   --no-build  Do not build the image if it is missing (exit with a hint instead)
#   --no-clone  Skip clone_cuvslam.sh
#
# After --, all arguments are passed to the Python script.
# Environment: KITTI_SEQUENCE, KITTI_USE_SYNTHETIC_DEMO (for bundled demo only), KITTI_SAVE_RRD, …

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
TAG="${CUVSLAM_DOCKER_TAG:-pycuvslam:realsense-cu13}"

DENSE=0
NO_BUILD=0
NO_CLONE=0
PY_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dense) DENSE=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --no-clone) NO_CLONE=1; shift ;;
    --save-rrd)
      # track_kitti_dense --save-rrd needs a value; a bare --save-rrd is invalid. Prefer KITTI_SAVE_RRD=...
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        PY_ARGS+=("--save-rrd" "$2")
        shift 2
      else
        # Use KITTI_SAVE_RRD in the environment (e.g. run_kitti_e2e_batch always sets it).
        shift
      fi
      ;;
    --) shift; PY_ARGS+=("$@"); break ;;
    -h|--help)
      sed -n '1,20p' "$0" | tail -n +2
      exit 0
      ;;
    *) PY_ARGS+=("$1"); shift ;;
  esac
done

if [[ "${NO_CLONE}" -eq 0 ]]; then
  bash "${ROOT_DIR}/scripts/clone_cuvslam.sh"
fi

if [[ ! -d "${CUVSLAM_DIR}" ]]; then
  echo "Error: CUVSLAM_DIR not found: ${CUVSLAM_DIR}" >&2
  exit 1
fi

if ! docker image inspect "${TAG}" &>/dev/null; then
  if [[ "${NO_BUILD}" -eq 1 ]]; then
    echo "Error: image ${TAG} not found. Build with: ${ROOT_DIR}/scripts/build_docker_spark.sh" >&2
    exit 1
  fi
  echo "Image ${TAG} not found; building (first time can take a long time)…" >&2
  bash "${ROOT_DIR}/scripts/build_docker_spark.sh"
fi

# Match scripts/run_cuvslam_docker.sh (X11, datasets, USB, video, working dir)
XSOCK=/tmp/.X11-unix
XAUTH=/tmp/.docker.xauth
touch "${XAUTH}"
xauth nlist "${DISPLAY:-}" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "${XAUTH}" nmerge - 2>/dev/null || true
chmod 777 "${XAUTH}" 2>/dev/null || true
DATASETS="${DATASETS:-$(realpath -s "${HOME}/datasets" 2>/dev/null || echo "${HOME}/datasets")}"
mkdir -p "${DATASETS}"
xhost +local:docker 2>/dev/null || true
VIDEO_ARGS=()
if compgen -G /dev/video* > /dev/null; then
  for dev in /dev/video*; do
    [[ -e "$dev" ]] && VIDEO_ARGS+=(--device="${dev}:${dev}")
  done
fi

# Without a real odometry sequence, the Python example exits unless synthetic demo is allowed.
# For this one-shot script only: opt into the bundled demo when 06 is missing and the user
# has not set KITTI_SEQUENCE or KITTI_USE_SYNTHETIC_DEMO.
_KITTI_SEQ_BASE="${CUVSLAM_DIR}/examples/kitti/dataset/sequences"
if [[ -z "${KITTI_SEQUENCE:-}" && -z "${KITTI_USE_SYNTHETIC_DEMO:-}" ]]; then
  if [[ ! -f "${_KITTI_SEQ_BASE}/06/calib.txt" && -f "${_KITTI_SEQ_BASE}/demo/calib.txt" ]]; then
    export KITTI_USE_SYNTHETIC_DEMO=1
    echo "run_kitti_e2e: no dataset/sequences/06 — using bundled synthetic demo. Add real KITTI under ${_KITTI_SEQ_BASE}/ for road imagery, or set KITTI_USE_SYNTHETIC_DEMO=0 and KITTI_SEQUENCE=…" >&2
  fi
fi

# Forward common env vars if set in the parent shell
ENV_ARGS=()
for v in KITTI_SEQUENCE KITTI_USE_SYNTHETIC_DEMO KITTI_SAVE_RRD KITTI_RERUN_SPAWN RERUN_FORCE_SPAWN; do
  if [[ -n "${!v:-}" ]]; then
    ENV_ARGS+=(-e "${v}=${!v}")
  fi
done
if [[ -n "${DISPLAY:-}" ]]; then
  ENV_ARGS+=(-e "DISPLAY=${DISPLAY}")
fi
if [[ -n "${RERUN_FORCE_SPAWN:-}" ]]; then
  ENV_ARGS+=(-e "RERUN_FORCE_SPAWN=${RERUN_FORCE_SPAWN}")
fi

cleanup() { xhost -local:docker 2>/dev/null || true; }
trap cleanup EXIT

# shellcheck disable=SC2016,SC2046,SC2086
set +e
docker run --rm -i \
  --gpus all \
  --runtime=nvidia \
  --privileged \
  --network host \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e XAUTHORITY="${XAUTH}" \
  -e QT_X11_NO_MITSHM=1 \
  -e _X11_NO_MITSHM=1 \
  -e _MITSHM=0 \
  -e "KITTI_E2E_DENSE=${DENSE}" \
  -e CUVSLAM_QUIET_NANOBIND=1 \
  "${ENV_ARGS[@]}" \
  -v "${XSOCK}":"${XSOCK}" \
  -v "${XAUTH}":"${XAUTH}" \
  -v "${CUVSLAM_DIR}":/cuvslam \
  -v "${DATASETS}":"${DATASETS}" \
  "${VIDEO_ARGS[@]}" \
  -v /dev/bus/usb:/dev/bus/usb \
  -w /cuvslam \
  -v "${ROOT_DIR}/scripts/kitti_docker_entry.sh":/kitti_docker_entry.sh:ro \
  "${TAG}" \
  bash /kitti_docker_entry.sh "${PY_ARGS[@]}"
_E2E_EXIT=$?
set -e
if [[ "${_E2E_EXIT}" -eq 0 && -n "${KITTI_SAVE_RRD:-}" && "${KITTI_SAVE_RRD}" == /cuvslam/* ]]; then
  _HOST_RRD="${CUVSLAM_DIR}/${KITTI_SAVE_RRD#/cuvslam/}"
  echo "" >&2
  echo "Rerun .rrd on this machine (for scp to Mac, AirDrop, or Cloud): ${_HOST_RRD}" >&2
  if [[ -f "${_HOST_RRD}" ]]; then
    ls -la "${_HOST_RRD}" >&2
  else
    echo "  (file not found on host yet — check mount and path)" >&2
  fi
  echo "  On the Mac: rerun <file.rrd>   (match Rerun app version to examples/requirements.txt rerun-sdk)" >&2
fi
exit "${_E2E_EXIT}"
