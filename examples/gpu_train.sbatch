#!/bin/bash
# Hand-written GPU job. Submit with: eng sbatch examples/gpu_train.sbatch
#SBATCH --job-name=gpu-train
#SBATCH --partition=mit_normal_gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=%x-%j.out

module load miniforge
eval "$(conda shell.bash hook)"
conda activate myenv

nvidia-smi
python train.py --epochs 10
