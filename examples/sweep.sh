#!/bin/bash
# Hyperparameter sweep as a job array: 12 tasks, at most 2 running at once (2-GPU QoS cap).
# Each task picks its learning rate from the list by $SLURM_ARRAY_TASK_ID.
eng submit -J lr-sweep -g 1 -t 2:00:00 -a 0-11%2 --conda myenv -- \
  'LRS=(1e-2 3e-3 1e-3 3e-4 1e-4 3e-5 1e-2 3e-3 1e-3 3e-4 1e-4 3e-5); SEED=$((SLURM_ARRAY_TASK_ID / 6));
   python train.py --lr ${LRS[$SLURM_ARRAY_TASK_ID]} --seed $SEED'
