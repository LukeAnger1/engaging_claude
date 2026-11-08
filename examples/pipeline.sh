#!/bin/bash
# Preprocess on CPU, then train on 2 GPUs only if preprocessing succeeds.
set -e
PRE=$(eng submit -J prep -c 32 -m 128G -t 3:00:00 -- python prep.py | awk '/Submitted job/{print $3}')
eng submit -J train -g 2 --gpu-type h100 -t 6:00:00 -d "$PRE" --conda myenv -- \
  torchrun --nproc_per_node=2 train.py
