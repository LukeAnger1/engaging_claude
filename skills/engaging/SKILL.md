---
name: engaging
description: Run batch jobs, CPU jobs and GPU jobs on the MIT Engaging Slurm cluster with the `eng` command. Use whenever the user wants to run something on Engaging / the cluster / Slurm, submit or monitor jobs, request GPUs or more compute (CPUs, memory, time, nodes), run job arrays or parameter sweeps, chain jobs, check the queue, read job logs, cancel jobs, or find which GPUs and partitions are available.
allowed-tools: Bash(eng check), Bash(eng config), Bash(eng help), Bash(eng status:*), Bash(eng logs:*), Bash(eng wait:*), Bash(eng history:*), Bash(eng efficiency:*), Bash(eng partitions), Bash(eng resources:*), Bash(eng gpus), Bash(eng limits), Bash(eng quota), Bash(eng modules:*), Bash(eng interactive:*)
---

# Engaging Slurm jobs with `eng`

`eng` is in the engaging_claude repo's `bin/` (on PATH after `source shell/ccl.bashrc`).
Run `eng help` for all commands and `eng submit --help` for every resource flag.

## Start here

```bash
eng check
```

- `CONNECTED (local mode)`: you are on Engaging (for example inside a `ccl` session). Slurm commands run directly.
- `CONNECTED (ssh mode)`: you are on a laptop and the user's SSH connection is open.
- `no live SSH connection`: ask the user to run `eng connect` in their own terminal (password + Duo). You cannot do Duo. Don't retry in a loop.

## Choose how to run

| Need | Command |
|---|---|
| Long work, training, anything > ~15 min | `eng submit [resources] -- <command>`, then monitor it |
| Short compute where you need the output now | `eng srun [resources] -- <command>` (blocks until done) |
| The user already has an sbatch script | `eng sbatch job.sbatch` |
| An interactive shell or Jupyter | `eng interactive [resources]`, then give the user the printed `salloc` line |

Don't run heavy compute in the current shell. Inside a `ccl` session your own shell only has
the GPUs that `ccl -t` gave you.

The job runs in the current directory by default (`-C DIR` to change it). Its stdout and stderr go
to `~/.ccl/jobs/logs/<name>-<jobid>.out`.

## Requesting compute

- CPU: `-c 16 -m 64G -t 4:00:00`. The default is 1 CPU, 4G, 1 hour, on `mit_normal`.
- GPU: `-g 1` picks the GPU partition (`mit_normal_gpu`). The default is 8 CPUs and 64G per GPU.
  Pick a model with `--gpu-type l40s|h100|h200|b200`.
- Job array / sweep: `-a 0-19%4`. Use `$SLURM_ARRAY_TASK_ID` inside the command, in single quotes.
- Chain jobs: `-d <jobid>` starts this job after that one succeeds.
- Software: `--conda ENV`, `--venv PATH`, `-M module` (repeatable), `-e KEY=VAL`.
- Multi-node: `-N 2 --ntasks-per-node 32`, or `--exclusive`.
- Debug run that starts fast: `--test`.

**Limits on `mit_normal_gpu`:** each user can hold at most 2 GPUs, 32 CPUs and 515G at once, and a job can run for at most 6 hours.
A `ccl` session's own GPUs count toward the 2-GPU cap, so a GPU job submitted from inside
`ccl` can pend (`QOSMaxGRESPerUser`) until the session ends. To get more GPUs or more time,
use `--preemptable --requeue` (`mit_preemptable`: up to 2 days, but the job can be killed,
so the code must checkpoint and resume). `eng` prints a warning when a request is over these limits.
Tell the user about the warning; don't silently change the request.

Before a big request, look first:
- `eng gpus`: GPU types and how many are in use
- `eng partitions`
- `eng resources mit_normal_gpu`
- `eng limits`

Always run with `--dry-run` first. Show the user the script before submitting
anything with more than 1 GPU, a time over 6 hours, or an array over 20 tasks.

## Monitoring

- `eng status`: your whole queue. `eng status <id>`: one job's state, estimated start, or final accounting.
- `eng logs <id>`: the last 100 lines. Use `-n 300`, `--all`, or `-f` to follow until the job ends.
- `eng wait <id>`: blocks until the job is done. Exits with 1 if any task failed. For long jobs,
  run it in the background and report back when it finishes.
- `eng efficiency <id>`: real CPU and memory use. Use it to size the next request.
- How to read the state:

  | State or reason | What to do |
  |---|---|
  | `PENDING (Resources/Priority)` | Wait |
  | `QOSMaxGRESPerUser` | Over the GPU cap |
  | `OUT_OF_MEMORY` | Raise `-m` |
  | `TIMEOUT` | Raise `-t`, or checkpoint and use `--preemptable` |
  | `FAILED` | Read `eng logs` |

## Changing and cancelling

- `eng update <id> --time T | --partition P | --hold | --release`. This mostly works only on pending jobs.
- `eng cancel <id>`, `eng cancel --pending`, `eng cancel --name NAME`, `eng cancel --all`.
  Cancel skips the job you're running in and `ccl` server jobs. Never pass `--force` unless the user
  explicitly asks. Ask the user before `--all`.
