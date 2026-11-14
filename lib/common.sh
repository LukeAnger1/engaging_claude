# shellcheck shell=bash
# Shared config + helpers for ccl / ccl-setup. Sourced, not executed.

CCL_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ============================ CONFIG ============================
# Engaging (MIT ORCD) defaults. Override any of these in
# $CCL_REPO/config.local.sh (gitignored) or via the environment.

# Slurm. mit_normal_gpu: L40S/H100/H200/B200, 6h max, QoS cap 2 GPUs / 32 CPU / 515G per user.
: "${CCL_PARTITION:=mit_normal_gpu}"
: "${CCL_GPU_TYPE:=l40s}"          # l40s (most nodes), h100, h200, b200, or empty = any
: "${CCL_TIME:=04:00:00}"          # must be <= partition limit (06:00:00)
: "${CCL_CPUS_PER_GPU:=8}"
: "${CCL_MEM_PER_GPU:=64G}"
: "${CCL_SALLOC_EXTRA:=}"          # e.g. "-A mit_general --qos=..." (not needed on mit_normal_gpu)

# Big files (venv, weights, caches) live on pool, never in $HOME.
: "${CCL_DATA:=$HOME/orcd/pool/ccl}"
: "${CCL_VENV:=$CCL_DATA/venv}"
: "${CCL_MODELS_DIR:=$CCL_DATA/models}"
: "${CCL_PYTHON:=3.12}"
: "${CCL_VLLM_SPEC:=vllm}"         # pin e.g. "vllm==0.11.0" if the driver/CUDA mismatch

# Small state (PID files, logs, mode, default model) lives in $HOME.
: "${CCL_STATE:=$HOME/.ccl}"
: "${CCL_MODELS_CONF:=$CCL_REPO/models.conf}"

# What plain `claude` / `ccl local` starts when nothing is running.
: "${CCL_DEFAULT_ARGS:=-t 1}"

# Seconds to wait for vLLM /health.
: "${CCL_READY_TIMEOUT:=1800}"

# ccl multi: one model across several sbatch jobs (each request is capped at 2 GPUs).
: "${CCL_MULTI_JOBS:=2}"           # number of jobs (-n)
: "${CCL_MULTI_GPUS_PER_JOB:=2}"   # GPUs per job when -l isn't given (head job: model + -t)
: "${CCL_MULTI_ENV:=}"             # extra VAR=value for Ray/vLLM on every node, e.g. "NCCL_SOCKET_IFNAME=ib0"
: "${CCL_MULTI_IP_CMD:=}"          # command printing this node's IP, if `getent hosts $(hostname)` is wrong

# ---- eng (general Slurm jobs: bin/eng) ----
: "${ENG_MODE:=auto}"                    # auto | local (sbatch on PATH) | ssh (from a laptop)
: "${ENG_CPU_PARTITION:=mit_normal}"
: "${ENG_GPU_PARTITION:=$CCL_PARTITION}"
: "${ENG_PREEMPT_PARTITION:=mit_preemptable}"   # 2 days, may be preempted
: "${ENG_TEST_PARTITION:=mit_quicktest}"
: "${ENG_GPU_TYPE:=any}"                 # default --gpu-type for eng jobs (any = no constraint)
: "${ENG_MAX_GPUS:=2}"                   # per-user QoS GPU cap on ENG_GPU_PARTITION (warning only)
: "${ENG_GPU_MAX_TIME:=06:00:00}"        # time limit of ENG_GPU_PARTITION (warning only)
: "${ENG_CPU_MAX_TIME:=12:00:00}"        # time limit of ENG_CPU_PARTITION (warning only)
: "${ENG_ACCOUNT:=}"
: "${ENG_DEFAULT_MODULES:=}"             # loaded in every eng job, e.g. "miniforge"
: "${ENG_WORKDIR:=}"                     # empty = current dir (local) or ~ (ssh)
: "${ENG_LOG_DIR:=~/.ccl/jobs/logs}"     # job stdout+stderr ('~' expands on the cluster)
: "${ENG_JOB_DIR:=~/.ccl/jobs/scripts}"  # generated sbatch scripts
# ssh mode (running eng on your laptop):
: "${ENG_USER:=${USER:-}}"               # your Kerberos username
: "${ENG_HOST:=orcd-login001.mit.edu}"
: "${ENG_CONTROL_PATH:=$HOME/.ssh/eng-cm-%r@%h:%p}"
: "${ENG_CONTROL_PERSIST:=12h}"
# ================================================================

[[ -f "$CCL_REPO/config.local.sh" ]] && source "$CCL_REPO/config.local.sh"

CCL_RUN_DIR="$CCL_STATE/run"
CCL_BIN="$CCL_REPO/bin/ccl"

# Caches that would otherwise land in $HOME.
export HF_HOME="${HF_HOME:-$CCL_DATA/hf}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$CCL_DATA/uv-cache}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

die()  { echo "ccl: $*" >&2; exit 1; }
warn() { echo "ccl: $*" >&2; }
info() { echo "ccl: $*" >&2; }

# Real Claude Code binary (never the shell function).
real_claude() {
  if [[ -n "${CCL_CLAUDE_BIN:-}" ]]; then echo "$CCL_CLAUDE_BIN"; return; fi
  local p; p="$(type -P claude)" || true
  [[ -n "$p" ]] || p="$HOME/.local/bin/claude"
  echo "$p"
}

# ---- models.conf ----
# Prints the registry line (sans comments) for a model name; nonzero if missing.
model_line() {
  awk -v n="$1" '!/^[[:space:]]*(#|$)/ && $1==n { print; found=1; exit } END { exit !found }' "$CCL_MODELS_CONF"
}
model_names() { awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$CCL_MODELS_CONF"; }
# Sets M_NAME M_REPO M_PARSER M_MIN_GPUS M_MAX_LEN M_EXTRA (array)
load_model() {
  local line; line="$(model_line "$1")" || die "unknown model '$1' (see: ccl-setup list)"
  read -r M_NAME M_REPO M_PARSER M_MIN_GPUS M_MAX_LEN M_EXTRA_STR <<<"$line"
  read -r -a M_EXTRA <<<"${M_EXTRA_STR:-}"
}
model_path()   { echo "$CCL_MODELS_DIR/$1"; }
model_pulled() { [[ -f "$CCL_MODELS_DIR/$1/.ccl-complete" ]]; }

default_model() {
  if [[ -s "$CCL_STATE/default_model" ]]; then cat "$CCL_STATE/default_model"
  else model_names | head -1; fi
}

get_mode() { [[ -s "$CCL_STATE/mode" ]] && cat "$CCL_STATE/mode" || echo local; }
