#!/usr/bin/env bash
# After unpacking KITTI odometry (e.g. data_odometry_gray.zip) you get
#   dataset/sequences/00, 01, … under some folder. This script runs
#   scripts/run_kitti_e2e.sh once per sequence and writes a separate Rerun
#   recording per “clip” (e.g. kitti_00.rrd) under
#   cuVSLAM/examples/kitti/rerun_out/  (in-container: /cuvslam/examples/kitti/rerun_out).
#
# The sequences root is resolved in this order (first with calib.txt for 00 or demo wins):
#   1) KITTI_SEQUENCES_DIR if set
#   2) CUVSLAM_DIR/examples/kitti/dataset/sequences
#   3) $DATASETS/kitti/dataset/sequences (or $HOME/datasets if DATASETS unset)
#   4) $DATASETS/dataset/sequences
#
# If the root is the cuVSLAM example path, KITTI_SEQUENCE=00 is passed (short name).
# If the root is elsewhere, the full path is passed; it must be visible in Docker (same
# path on host as under the DATASETS mount used by run_kitti_e2e.sh).
#
# “Closed loop”-friendly training sequences are 00, 02, 05, 07, 08, 09 (and others; see
#   cuVSLAM/examples/kitti/README.md). One odometry zip contains many sequence folders.
#
# Usage (from sandbox repo root, GPU host):
#   ./scripts/run_kitti_e2e_batch.sh
#   ./scripts/run_kitti_e2e_batch.sh 00 01 02 05 07 08 09
#   RRD_BASENAME=/cuvslam/examples/kitti/my_runs ./scripts/run_kitti_e2e_batch.sh
#   ./scripts/run_kitti_e2e_batch.sh --no-clone -- 00 05
#   RUN_KITTI_DEMO_WHEN_EMPTY=0 ./scripts/run_kitti_e2e_batch.sh   # do not fall back to demo
#
# Each run sets KITTI_SAVE_RRD=… in the container so .rrd files are written; do *not* pass
#   bare --save-rrd to this script. Use: ./run_kitti_e2e_batch.sh --dense
#
# Optional env: CUVSLAM_DIR, CUVSLAM_DOCKER_TAG, KITTI_SEQUENCES_DIR, DATASETS, RUN_KITTI_DEMO_WHEN_EMPTY (default 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CUVSLAM_DIR="${CUVSLAM_DIR:-${ROOT_DIR}/cuVSLAM}"
_DATASETS_DEFAULT="${DATASETS:-${HOME}/datasets}"
RUN_KITTI_DEMO_WHEN_EMPTY="${RUN_KITTI_DEMO_WHEN_EMPTY:-1}"

# Default: six training sequences often used for revisits / loop-style behaviour.
DEFAULT_SEQS=(00 02 05 07 08 09)

CUVSLAM_KITTI_SEQ="${CUVSLAM_DIR}/examples/kitti/dataset/sequences"

_discover_kitti_sequences_dir() {
  if [[ -n "${KITTI_SEQUENCES_DIR:-}" ]]; then
    echo "${KITTI_SEQUENCES_DIR}"
    return
  fi
  local c
  for c in \
    "${CUVSLAM_KITTI_SEQ}" \
    "${_DATASETS_DEFAULT}/kitti/dataset/sequences" \
    "${_DATASETS_DEFAULT}/dataset/sequences"; do
    if [[ -f "${c}/00/calib.txt" || -f "${c}/demo/calib.txt" ]]; then
      echo "${c}"
      return
    fi
  done
  echo "${CUVSLAM_KITTI_SEQ}"
}

# short name (00) for cuVSLAM tree; else absolute path so Docker sees $DATASETS/... copies.
_kitti_seq_env_value() {
  local s="$1"
  if [[ "${_KITTI_BASE}" == "${CUVSLAM_KITTI_SEQ}" ]]; then
    echo "${s}"
  else
    echo "${_KITTI_BASE}/${s}"
  fi
}

E2E_EXTRA=()
NO_CLONE=0
REQ_SEQS=()
parsing=1
while [[ $# -gt 0 ]]; do
  if [[ "$parsing" -eq 1 ]]; then
    case "$1" in
      --no-clone) NO_CLONE=1; shift ;;
      --) parsing=0; shift ;;
      -h|--help)
        sed -n '1,40p' "$0" | tail -n +2
        exit 0
        ;;
      *)
        if [[ "$1" == --* ]]; then
          E2E_EXTRA+=("$1")
        else
          REQ_SEQS+=("$1")
        fi
        shift
        ;;
    esac
  else
    REQ_SEQS+=("$1")
    shift
  fi
done

if [[ ${#REQ_SEQS[@]} -eq 0 ]]; then
  REQ_SEQS=("${DEFAULT_SEQS[@]}")
fi

if [[ ! -d "${CUVSLAM_DIR}" ]]; then
  echo "Error: CUVSLAM_DIR not found: ${CUVSLAM_DIR} (run scripts/clone_cuvslam.sh or set CUVSLAM_DIR)" >&2
  exit 1
fi

_KITTI_BASE="$(_discover_kitti_sequences_dir)"
RRD_BASENAME="${RRD_BASENAME:-/cuvslam/examples/kitti/rerun_out}"
# Host path: .rrd files appear here; inside Docker they are under /cuvslam/...
_RRD_HOST="${CUVSLAM_DIR}/examples/kitti/rerun_out"
mkdir -p "${_RRD_HOST}"
NO_CLONE_ARGS=()
if [[ "${NO_CLONE}" -eq 1 ]]; then
  NO_CLONE_ARGS=(--no-clone)
fi

echo "run_kitti_e2e_batch: KITTI sequences root: ${_KITTI_BASE}" >&2

_run_one() {
  local s="$1"
  local rrd="$2"
  local kseq
  kseq="$(_kitti_seq_env_value "${s}")"
  echo "=== KITTI_SEQUENCE=${kseq} KITTI_SAVE_RRD=${rrd} ===" >&2
  KITTI_SEQUENCE="${kseq}" \
  KITTI_USE_SYNTHETIC_DEMO=0 \
  KITTI_SAVE_RRD="${rrd}" \
    bash "${ROOT_DIR}/scripts/run_kitti_e2e.sh" \
      "${NO_CLONE_ARGS[@]}" \
      "${E2E_EXTRA[@]}"
}

n_ok=0
n_skip=0
for s in "${REQ_SEQS[@]}"; do
  c="${_KITTI_BASE}/${s}/calib.txt"
  if [[ ! -f "${c}" ]]; then
    echo "run_kitti_e2e_batch: skip sequence ${s} (missing ${c})." >&2
    n_skip=$((n_skip + 1))
    continue
  fi
  out_rrd="${RRD_BASENAME}/kitti_${s}.rrd"
  _run_one "${s}" "${out_rrd}"
  n_ok=$((n_ok + 1))
done

if [[ "${n_ok}" -eq 0 && "${RUN_KITTI_DEMO_WHEN_EMPTY}" != "0" && "${RUN_KITTI_DEMO_WHEN_EMPTY}" != "false" ]]; then
  if [[ -f "${_KITTI_BASE}/demo/calib.txt" ]]; then
    echo "run_kitti_e2e_batch: no training sequences from your list; running bundled synthetic demo once (set RUN_KITTI_DEMO_WHEN_EMPTY=0 to skip)." >&2
    _run_one "demo" "${RRD_BASENAME}/kitti_demo.rrd"
    n_ok=1
  fi
fi

echo "run_kitti_e2e_batch: done. ok=${n_ok} skip=${n_skip} out=${_RRD_HOST}/" >&2
if [[ "${n_ok}" -eq 0 ]]; then
  echo "run_kitti_e2e_batch: unpack KITTI (http://www.cvlibs.net/datasets/kitti/eval_odometry.php) so you have e.g. .../dataset/sequences/00/calib.txt" >&2
  echo "  or set KITTI_SEQUENCES_DIR to your .../dataset/sequences folder, or place data under \${DATASETS}/kitti/dataset/sequences (mounted into Docker like run_kitti_e2e.sh)." >&2
  exit 1
fi
