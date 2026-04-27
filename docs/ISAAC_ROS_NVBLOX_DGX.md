# nvblox + cuVSLAM on DGX Spark (Isaac ROS)

This **sandbox** repo’s **`pycuvslam:realsense-cu13`** image is for **PyCuVSLAM** (Python examples, TUM, KITTI, `track_mono_mp4`, etc.). It does **not** ship [Isaac ROS Nvblox](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox) or a ROS 2 graph.

NVIDIA’s **supported** way to build a **3D / 2D costmap** with **depth + VSLAM** is a **separate** stack:

- **Isaac ROS Nvblox** — GPU TSDF / reconstruction / Nav2 costmaps.
- **Isaac ROS Visual SLAM** — ROS 2 wrapper around **cuVSLAM** (pose to `nvblox`).

The upstream **RealSense** launch file `realsense_example.launch.py` already **starts RealSense, Visual SLAM, and nvblox** together (see [RealSense + nvblox tutorial](https://nvidia-isaac-ros.github.io/concepts/scene_reconstruction/nvblox/tutorials/tutorial_realsense.html) and the [nvblox examples bringup](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox) package).

## Why not add nvblox to `Dockerfile.realsense-cu13`?

- **Isaac ROS** is distributed as a **curated** workspace: `isaac_ros_common` dev image, NGC/APT packages, and a pinned ROS distro — not a `pip install` on top of the cuVSLAM-only image.
- **Versions** of ROS, `isaac_ros_nvblox`, `isaac_ros_visual_slam`, and CUDA must **match** what NVIDIA tests (Jetson, x86, and **aarch64** systems including DGX-class platforms per current docs).
- Merging a full Isaac stack into this image would be **large**, **fragile**, and hard to keep aligned with releases.

**Practical approach:** use **Isaac’s dev container** (or a supported install) for **mapping**; keep **this** repo’s container for **offline PyCuVSLAM** and datasets.

## Recommended layout

| Path | Role |
|------|------|
| `…/sandbox-slam-cuVSLAM` | This repo: `cuVSLAM` clone, `build_docker_spark.sh`, TUM, mono video, Rerun |
| `…/isaac_ros_ws/src/…` | Isaac ROS workspace: `isaac_ros_common`, `isaac_ros_nvblox`, `isaac_ros_visual_slam`, … |

Run `./scripts/prepare_isaac_nvblox_workspace.sh` to shallow-clone into **`$HOME/isaac_ros_ws`** (override the directory with env **`NVBLOX_ISAAC_WS`**). **`ISAAC_ROS_GITREF`** defaults to **`release-3.2`** so **`isaac_ros_common/scripts/run_dev.sh`** exists at the path used in older tutorials. On **`main`** (and some **release-4.x** layouts) that script was **removed** from the repo root; use the [current Isaac ROS getting started](https://nvidia-isaac-ros.github.io/getting_started/index.html) flow for newer releases, or stay on **release-3.2** for the classic `run_dev.sh` entrypoint.

If you already cloned **`main`** earlier, the script will **skip** existing directories and leave you on the wrong branch. Either remove the three `isaac_ros_*` folders under `…/src/` or run **`ISAAC_NVBLOX_SYNC=1 ./scripts/prepare_isaac_nvblox_workspace.sh`** to delete and re-clone at **`ISAAC_ROS_GITREF`** (default `release-3.2`).

The script does **not** use **`ISAAC_ROS_WS`** for the clone path, so it will not follow a mistaken export that points at this repository.

If you already cloned into **this repo’s `src/`** using an old script, remove that folder and re-run, set `NVBLOX_ISAAC_WS` to a dedicated path, or move the three `isaac_ros_*` directories under `~/isaac_ros_ws/src/`.

## Steps (high level)

1. **Prerequisites on DGX Spark (aarch64):** Docker + NVIDIA Container Toolkit, RealSense (if using live camera), USB rules as in the [Nvblox / RealSense documentation](https://nvidia-isaac-ros.github.io/repositories_and_packages/isaac_ros_nvblox/index.html).

2. **Create an Isaac ROS workspace** and clone (at the **same** release tag / branch) at least:
   - [`isaac_ros_common`](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_common) — on **release-3.2**, `scripts/run_dev.sh` at the **git root** enters the **dev container** (newer branches may differ; see NVIDIA docs).
   - [`isaac_ros_nvblox`](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox) — `nvblox_examples_bringup`.
   - [`isaac_ros_visual_slam`](https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_visual_slam) — used by the nvblox RealSense graph.

3. **Enter the dev environment** (release-3.2 style). Run from your **Isaac workspace root** (e.g. `~/isaac_ros_ws`), not from this sandbox repo — `run_dev.sh` uses the current directory as the mount context:

   ```bash
   cd ~/isaac_ros_ws
   ./src/isaac_ros_common/scripts/run_dev.sh
   ```

   This uses the **NVIDIA Isaac ROS** image for your **architecture**. Follow the current [Getting Started](https://nvidia-isaac-ros.github.io/) page for options and CUDA/ROS requirements.

### NGC / Docker: `Access Denied` or `failed to fetch oauth token` when building

`run_dev.sh` builds layered images that **pull from `nvcr.io`** (e.g. `nvcr.io/nvidia/12.6.11-devel:…`). If Docker reports **Access Denied** on the OAuth token, the registry is treating you as **unauthenticated** or your key has no access to that repo.

1. Create an **NGC API key** (NVIDIA account): [NGC setup — API keys](https://org.ngc.nvidia.com/setup/api-keys).
2. Log Docker into NGC (password is the API key; username is the literal string **`$oauthtoken`** — keep the single quotes so the shell does not expand it):

   ```bash
   docker logout nvcr.io 2>/dev/null || true
   export NGC_API_KEY='paste-your-key-here'
   echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
   ```

3. Retry `run_dev.sh`. If it still fails, confirm the image name is pullable for your account tier and that no proxy/firewall strips `nvcr.io` auth.

**Note:** **release-3.2** targets **ROS 2 Humble** on **Ubuntu 22.04**-style CUDA bases — that may not match **DGX Spark + CUDA 13** the way `pycuvslam:realsense-cu13` does. For Spark-specific stacks, prefer the **current** Isaac ROS release docs (newer branches / `isaac-ros` CLI) once NGC login and `run_dev` entrypoints align with that release.

### DGX Spark: `unresolvable CDI devices nvidia.com/pva=all`

**DGX Spark** is **aarch64** but **not Jetson**. In **release-3.2**, `scripts/run_dev.sh` treats every `aarch64` host like a Jetson: it sets **`NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all`** and bind-mounts **Tegra** paths. **PVA** exists on Jetson, not on Spark → Docker CDI fails with **`nvidia.com/pva=all: unknown`**.

**Fix (recommended):** patch `run_dev.sh` so the Jetson-only block runs only on real Jetsons. **Do not** gate on `/usr/lib/aarch64-linux-gnu/tegra` alone — **DGX Spark can have that tree** while still lacking PVA CDI. Use **`/etc/nv_tegra_release`** (present on Jetson, absent on Spark):

```bash
cd ~/Development/sandbox-slam-cuVSLAM   # or your sandbox clone
./scripts/patch_isaac_run_dev_spark.sh
cd ~/isaac_ros_ws
./src/isaac_ros_common/scripts/run_dev.sh
```

The patch changes one line from `if [[ $PLATFORM == "aarch64" ]]; then` to  
`if [[ $PLATFORM == "aarch64" ]] && [[ -f /etc/nv_tegra_release ]]; then`  
so **Spark skips** PVA/Tegra mounts and keeps the earlier **`NVIDIA_VISIBLE_DEVICES=all`**.

If you applied an older sandbox patch that used the **tegra directory** check, re-run **`patch_isaac_run_dev_spark.sh`** once; it upgrades that line to **`nv_tegra_release`**.

**Security:** do **not** paste NGC API keys into chats or tickets. If a key was exposed, **revoke it** in [NGC API keys](https://org.ngc.nvidia.com/setup/api-keys) and create a new one; then `docker login nvcr.io` again.

4. **Inside the container:** `rosdep` and `colcon build` (exact commands in the nvblox [quickstart](https://nvidia-isaac-ros.github.io/repositories_and_packages/isaac_ros_nvblox/index.html); ROS 2 is often **Jazzy** on recent releases).

5. **Run RealSense + VSLAM + nvblox** (after sourcing the workspace):

   ```bash
   ros2 launch nvblox_examples_bringup realsense_example.launch.py
   ```

   See the [RealSense nvblox tutorial](https://nvidia-isaac-ros.github.io/concepts/scene_reconstruction/nvblox/tutorials/tutorial_realsense.html) for `rosbag`, `mode`, `run_rviz`, Foxglove, etc.

6. **Visualization:** default **RViz**; for remote, use **Foxglove** as in the tutorial.

### Benchmark: real-time throughput (Hz / “FPS”)

**Compile time** for `colcon build` is not frame rate; for **runtime** “can we keep up?” you want **ROS topic rates** (depth in, pose out, mesh out) plus **GPU** headroom.

This repo ships **`scripts/benchmark_nvblox_perf.sh`**. Run it in a **second terminal** while `realsense_example.launch.py` (or your bag replay) is running, **after** sourcing the same ROS + workspace as the launch:

```bash
source /opt/ros/humble/setup.bash
source ~/isaac_ros_ws/install/setup.bash
~/Development/sandbox-slam-cuVSLAM/scripts/benchmark_nvblox_perf.sh -d 45
```

It runs **`ros2 topic hz`** for several seconds in parallel on default **release-3.2 RealSense** topics (splitter depth, color, infra, `visual_slam/tracking/vo_pose`, `nvblox_node/mesh`), samples **`nvidia-smi`** once per second, writes **`summary.txt`** + per-topic logs under **`nvblox_bench_<timestamp>/`** in the sandbox repo (override with **`-o`** or **`NVBLOX_BENCH_OUT`**).

- **`--discover`**: merge topics from `ros2 topic list` matching `/camera0/`, `/nvblox_node/`, `/visual_slam/`.
- **`NVBLOX_BENCH_TOPICS="/a /b"`**: override the measured topic list.
- **Interpretation:** depth/color **average rate** near the camera’s configured FPS means the **sensor path** is real-time; if it **lags** under load, something upstream is dropping. **Mesh** (and similar) is often published slower than depth by design — compare to your **latency** requirements, not to raw camera FPS.

## Relating to this repo

- **VSLAM + cuVSLAM:** The Isaac node is the ROS path to **cuVSLAM** in the nvblox stack. **Python** scripts under `cuVSLAM/examples/` are a different entry (no nvblox).
- **`pycuvslam:realsense-cu13`:** use for TUM, KITTI, mono video, and Rerun `.rrd`. Use the **Isaac** container for **nvblox / Nav2** mapping.

**Rerun has no “nvblox panel.”** Rerun is a separate viewer. Examples such as `track_tum.py` log **poses, images, depth, and 2D/3D debug geometry** to Rerun — they do **not** run or embed **nvblox** (TSDF meshes, costmaps, `nvblox_msgs`, etc.). **nvblox** is a **ROS 2** node; NVIDIA documents it with **RViz** (and optionally **Foxglove** over ROS). To see nvblox output, use the **Isaac ROS** launch flow and RViz (or build a custom bridge that subscribes to nvblox topics and logs meshes/point clouds into Rerun yourself — not shipped here).

## References

- [Isaac ROS Nvblox](https://nvidia-isaac-ros.github.io/repositories_and_packages/isaac_ros_nvblox/index.html)
- [RealSense + nvblox + VSLAM](https://nvidia-isaac-ros.github.io/concepts/scene_reconstruction/nvblox/tutorials/tutorial_realsense.html)
- [Isaac ROS cuVSLAM](https://nvidia-isaac-ros.github.io/concepts/visual_slam/cuvslam/index.html)
- [cuVSLAM — ROS 2 (upstream)](https://github.com/nvidia-isaac/cuVSLAM/blob/main/README.md#ros2-support)
