#!/usr/bin/env bash
# Executed inside the PyCuVSLAM container (mounted by run_kitti_e2e.sh).
# Hides nanobind shutdown output (C-level stderr; not visible to sys.stderr in Python)
# when CUVSLAM_QUIET_NANOBIND is not 0, false, or no.
set -euo pipefail
cd /cuvslam

python3 -m pip install -q --break-system-packages -r examples/requirements.txt
if [[ "${KITTI_E2E_DENSE}" == 1 ]]; then
  python3 -m pip install -q --break-system-packages -r examples/kitti/requirements-dense-stereo.txt
  _py=examples/kitti/track_kitti_dense.py
else
  _py=examples/kitti/track_kitti.py
fi

_q="${CUVSLAM_QUIET_NANOBIND:-1}"
if [[ "${_q}" == 0 || "${_q}" == false || "${_q}" == no ]]; then
  exec python3 -u "${_py}" "$@"
fi

# -u: unbuffered stdout/stderr so messages keep chronological order with stderr piped.
# Filter: lines with nanobind/refleaks, and " - " bullet continuations.
set +e
python3 -u "${_py}" "$@" 2> >(
  stdbuf -o0 awk '!/nanobind/ && !/refleaks/ && $0 !~ /^ - / { print; fflush() }' >&2
)
_rc=$?
set -e
exit "${_rc}"
