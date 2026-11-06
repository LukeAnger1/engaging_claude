# engaging_claude: `ccl`, Claude Code on local LLMs on MIT Engaging

This repo deploys an open-weights LLM with vLLM on one or more Engaging GPUs and opens Claude Code
against it in your terminal. Plain `claude` uses the local model by default, and `claude --cloud`
uses your normal Anthropic login.

This is complete vibe code. Lets save that money.

## Quick start (login node)

```bash
git clone <this repo> ~/engaging_claude
~/engaging_claude/bin/ccl-setup install          # uv venv + vLLM + hf CLI on pool (~10 GB)
~/engaging_claude/bin/ccl-setup pull gpt-oss-20b # ~13 GB, downloaded on the login node
source ~/engaging_claude/shell/ccl.bashrc        # puts bin/ on PATH, defines `claude`
claude                                           # salloc -> vLLM -> Claude Code
```

To make the toggle permanent, add `source ~/engaging_claude/shell/ccl.bashrc` to `~/.bashrc`.

## Commands

| Command | What it does |
|---|---|
| `ccl [-m model] [-l N] [-t N] [-c ctx] [-k] [-g type] [-T time] [-- claude args]` | Starts (or reuses) a server and opens Claude Code |
| `ccl local` / `claude` | Attaches to a running server (this job first, then any of your running jobs), otherwise `ccl $CCL_DEFAULT_ARGS` |
| `ccl cloud` / `claude --cloud` | Normal Claude Code with your Anthropic login |
| `ccl batch [run options] [-o FILE] "prompt"` | Submits an sbatch job that runs one `-p` prompt (with `--dangerously-skip-permissions`), then stops the server and frees the GPUs |
| `ccl mode [local\|cloud]` | Sets what plain `claude` means |
| `ccl which` / `claude --which` | Shows what would happen |
| `ccl attach [jobid]` | Attaches Claude Code to a running server (`srun --overlap` if it's on another node) |
| `ccl status` / `ccl stop [jobid\|all]` | Lists or stops servers (`stop` cancels kept `-k` jobs) |
| `ccl-setup list\|pull\|default\|add\|remove\|login\|info` | Model registry and weights |

**Options:**
- `-l` is the number of GPUs for the model (tensor parallel).
- `-t` is the number of GPUs visible to Claude Code and everything it runs.
- The total `-l` + `-t` is what gets allocated.

**Examples:**
- `ccl -m qwen3-coder-30b-fp8 -l 1 -t 1` uses 1 GPU for the model and 1 GPU for your code.
- `ccl -m gpt-oss-120b -l 2 -t 0 -g h200 -T 2:00:00` puts a big model on 2 H200s.
- `claude -- -p "summarize this repo"` runs one-shot print mode on the local model.
- `ccl batch -m qwen3-coder-30b-fp8 -l 1 -t 1 -o output.txt "Summarize this repository"` runs Claude in batch mode with a preset prompt.

## Batch jobs (`ccl batch`)

`ccl batch` submits a Slurm job that starts vLLM, runs **one** Claude Code prompt (`-p`), then stops the server.
The job exits and the GPUs are freed. You don't need to stay logged in.

```bash
ccl batch [-m model] [-l N] [-t N] [-c ctx] [-g type] [-T time] [-p partition] [-o FILE] "prompt"
```

- It takes the same model and GPU options as `ccl`. `-k` is rejected, because batch always frees its resources.
- `-o FILE` sets where output goes. The default is `ccl-batch-<jobid>.out` in the directory you submitted from.
- Claude Code works in the directory you submit from.
- **Permissions:** batch runs Claude Code with `--dangerously-skip-permissions`, because nobody is there to
  approve tool calls. The model can edit and delete files and run any command as you. Submit from a
  directory you're comfortable letting it change.
- If you run it inside an existing Slurm job (e.g. a `salloc` shell), it runs right there instead of submitting.
- The model has to be downloaded first (`ccl-setup pull <name>`). Otherwise `ccl batch` refuses to submit.

**Use a specific model:**

```bash
ccl-setup list                                                    # see what's downloaded
ccl batch "Summarize this repository"                             # default model (ccl-setup default)
ccl batch -m qwen3-coder-30b-fp8 -l 1 -t 1 -o summary.txt "Summarize this repository"
ccl batch -m gpt-oss-120b -l 2 -t 0 -g h200 -T 1:00:00 "Review lib/common.sh for bugs"
```

**Read the prompt from a file or stdin:** if no prompt argument is given, `ccl batch` reads it from stdin.

```bash
ccl batch -m qwen3-coder-30b-fp8 -o review.txt < prompts/review.md
echo "Write unit tests for src/parser.py and run them" | ccl batch -t 1
```

**Call it from your own scripts:** `ccl batch` returns right after submitting, so you can loop over
prompts or projects. Each call is its own job with its own GPUs. The QoS cap is 2 GPUs per user, so
extra jobs just wait in the queue.

```bash
#!/bin/bash
# run_reviews.sh: one batch job per project directory
mkdir -p ~/reviews
for dir in ~/projects/*/; do
  ( cd "$dir" && ccl batch -m qwen3-coder-30b-fp8 -l 1 -t 0 -T 0:30:00 \
      -o "$HOME/reviews/$(basename "$dir").txt" \
      "Review this project and list the top 5 bugs with file:line references" )
done
squeue --me -n ccl-batch                          # watch the jobs
```

```bash
# one job per prompt file
mkdir -p results
for f in prompts/*.md; do
  ccl batch -o "results/$(basename "$f" .md).txt" < "$f"
done
```

The directory for `-o` must already exist, or Slurm drops the output.

Use `squeue --me -n ccl-batch` to check on jobs and `scancel <jobid>` to cancel one. Server logs are at
`~/.ccl/run/<jobid>.<model>.log`.

## How it works

- **No Slurm job:**
  - Without `-k`, `ccl` runs `salloc ... srun --pty ccl run ...`. Everything is released when Claude Code exits.
  - With `-k`, `ccl` submits an `sbatch` job (`ccl-serve`) that runs vLLM until walltime or `ccl stop`, then attaches through `srun --overlap`.

  The `-k` case needs a separate job because Engaging uses `proctrack/cgroup`: when a step ends, Slurm kills every process in it, even `setsid` ones.
- **`-k` inside a job:** the server lives as long as the step that started it. In a `salloc` shell
  (the interactive step), that's until you exit the shell. In a one-off `srun ... ccl -k`, it dies with that
  step (`ccl` warns about this). For a server that outlives your terminal, use `-k` from the login node.
- **Inside a job:** `ccl` uses the visible GPUs. The first `-l` go to vLLM and the next `-t` go to Claude Code, which runs with `CUDA_VISIBLE_DEVICES` set to only those. If the shell has no GPUs (for example a `salloc --no-shell` job), `ccl` hops onto the allocation with `srun --overlap --pty`.
- **vLLM:**
  - It runs under `setsid`, bound to `127.0.0.1` on a random port, with `HF_HUB_OFFLINE=1`.
  - It serves the model under its short name and exposes Anthropic's `/v1/messages`.
  - Ctrl-C in Claude Code does not reach it.
- **Server reuse:** state is kept in `~/.ccl/run/<jobid>.env`. The same model on the same GPUs is reused, and a different model replaces the old server.

## Engaging specifics

- **Account:** `mit_general` (no `-A` needed).
- **Partition:** `mit_normal_gpu`.
  - GPUs: L40S (48 GB, most nodes), H100, H200, and B200.
  - Time limit: 6 h.
  - QoS cap per user: **2 GPUs, 32 CPUs, 515 GB**.
- **Defaults:** `l40s`, 8 CPUs and 64 GB per GPU, 4 h. `mit_preemptable` allows 2 days, but jobs can be preempted.
- `LaunchParameters=use_interactive_step`: a plain `salloc` drops you into a shell on the compute node with the GPUs visible, so `ccl` works directly inside it.
- **Storage:** everything big lives in `~/orcd/pool/ccl`: the venv, `models/<name>`, `hf/` (`HF_HOME`), the uv cache, and the vLLM/triton caches. `$HOME` (200 GB) only holds `~/.ccl` (state, logs, mode).
- **No CUDA toolkit or nvcc on compute nodes.** vLLM's FlashInfer sampler fails with "Could not find nvcc"
  unless the prebuilt kernels are installed. `ccl-setup install` handles this by running `python -m flashinfer download-kernels`.
  If you upgrade vLLM by hand, rerun `ccl-setup install`.
- **Tested versions (2026-11):** vLLM 0.33.0, torch 2.14 (CUDA 13.0), driver 590.48 on L40S, Claude Code 2.1.318.
  gpt-oss-20b loads in about 60 s on 1 L40S, and in about 80 s with TP=2.
- **`srun --overlap` attach steps see the job's GPUs**, so `ccl attach` from another SSH session gets the task GPUs.
- Claude Code doesn't know local model IDs, so `ccl` sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the server's
  `--max-model-len`. Auto-compaction then happens before vLLM rejects a request. Ignore the "doesn't recognize the model" notice.
- The system `python3` is 3.6. The venv uses Python 3.12 through uv.
- `nvidia-smi` ignores `CUDA_VISIBLE_DEVICES`. To check what Claude Code can use, run `python -c "import torch;print(torch.cuda.device_count())"`.

## Configuration

Edit the CONFIG block in `lib/common.sh`, or override values in `config.local.sh` (gitignored) or the
environment. The main settings are `CCL_PARTITION`, `CCL_GPU_TYPE`, `CCL_TIME`, `CCL_DATA`,
`CCL_VLLM_SPEC`, and `CCL_DEFAULT_ARGS` (what plain `claude` starts with, default `-t 1`).

Per-run extras:
- `CCL_VLLM_EXTRA="--enable-prefix-caching ..."`
- `CCL_ATTACH_SRUN_EXTRA="--gres=gpu:2"` for attach steps

## Pull a model, make it the default, and confirm it runs

Run these steps on the **login node**, because compute nodes may not have internet access. The example uses
`qwen3-coder-30b-fp8`. Swap in any name from `ccl-setup list`.

**1. Pick a model and download it.** Weights go to `~/orcd/pool/ccl/models/<name>`.

```bash
ccl-setup list                       # [x] = downloaded, * = current default
ccl-setup pull qwen3-coder-30b-fp8   # ~31 GB, takes a few minutes
```

For gated models (for example Llama), run `ccl-setup login` once with a Hugging Face token first.
For a model that isn't listed yet, register it with `ccl-setup add` (see [Models](#models-modelsconf)), then pull it.

**2. Make it the model that plain `claude` and `ccl` run.**

```bash
ccl-setup default qwen3-coder-30b-fp8
ccl-setup list                       # the model should now show [x]*
ccl which                            # "... would salloc ... and start qwen3-coder-30b-fp8 (L=1, T=1, ...)"
```

To use a model for a single run without changing the default, use `ccl -m <name>`.

**3. Confirm it runs with a local Claude instance.**

Quick non-interactive check (allocates GPUs, answers, then releases them):

```bash
mkdir -p ~/ccl-check && cd ~/ccl-check
ccl -- -p "Reply with exactly: LOCAL-OK"
```

Expect `ccl: starting vLLM: qwen3-coder-30b-fp8 ...`, then `ccl: vLLM ready after Ns`, then `LOCAL-OK`.
Waiting in the queue and loading the model can each take a few minutes.

Full interactive check, which also confirms the model can use tools and sees the right GPUs:

```bash
source ~/engaging_claude/shell/ccl.bashrc   # if not already in ~/.bashrc
claude                                      # local model by default
```

Inside Claude Code:
- Run `/status`. The model should be `qwen3-coder-30b-fp8` and the base URL `http://127.0.0.1:<port>`, not Anthropic.
- Ask: *"Create hello.py that prints `torch.cuda.device_count()` using `~/orcd/pool/ccl/venv/bin/python`, then run it."*
  If the file gets created and run, tool calls work. The printed number should equal `-t` (1 by default).

Exit Claude Code. Without `-k`, the server and the job stop on their own. Check with `ccl status` (should say
"no ccl servers running") and `squeue --me`. If something fails, look at the server log at `~/.ccl/run/<jobid>.<model>.log`.

## Models (`models.conf`)

Columns: `name hf_repo tool_parser min_gpus max_len [extra vllm args]`. The `min_gpus` values are sized for L40S.
The tool parser must match the model family (`openai` for gpt-oss, `qwen3_coder`, `glm45`, `hermes`, ...).
Otherwise Claude Code can't edit files or run commands.

```bash
ccl-setup add glm-4.5-air zai-org/GLM-4.5-Air-FP8 glm45 2 65536
ccl-setup pull glm-4.5-air && ccl-setup default glm-4.5-air
```

## Troubleshooting

- **Out of memory at load:** lower `-c`, raise `-l`, or pick an FP8 or smaller model.
- **vLLM rejects Claude Code fields** (`thinking`, `cache_control`, ...): upgrade vLLM (`CCL_VLLM_SPEC`) or put a
  LiteLLM proxy or [claude-vllm](https://github.com/Nachetecabrera/claude-vllm) in front.
- **Server logs:** `~/.ccl/run/<jobid>.<model>.log`. Logs for kept `-k` jobs are in `~/.ccl/run/<jobid>.out`.
- **Never put `ANTHROPIC_BASE_URL` in `~/.claude/settings.json`.** It breaks cloud mode.
