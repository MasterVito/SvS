set -x
export WANDB_API_KEY="Your_wandb_api_key"
export HF_TOKEN="Your_huggingface_token"
export RAY_BACKEND_LOG_LEVEL=error
export NUM_GPUS=$(nvidia-smi --list-gpus | wc -l)

## model, file and save path 
experiment_name='Run_SvS_xB_Training'
model_name_or_path=Qwen/Qwen2.5-3B-Instruct
train_path=data/MATH_12k.parquet  # training data path
test_path=data/MATH-AIME-Evaluation.parquet
save_path=/path/to/your_save_path # define the path for saving RL intermediate checkpoints

## system parameters
use_chat_template=True
val_before_train=True # set to 1 to launch validation before inference
use_dynamic_bsz=True
tensor_model_parallel_size=1 # rollout and training batch size
use_tqdm=True # whether using tqdm in vLLM generation
save_freq=4
test_freq=8

## training parameters
total_epochs=30
train_batch_size=256
ppo_mini_batch_size=256
log_prob_micro_batch_size_per_gpu=2
kl_coef=0.0
kl_loss_coef=0.0
n_samples=8
max_prompt_length=4096 
max_response_length=8192
ppo_max_token_len_per_gpu=$((max_prompt_length + max_response_length))
estimator=grpo
use_kl_loss=$( [ "$(echo "$kl_loss_coef > 0.0" | bc)" -eq 1 ] && echo true || echo false )
use_kl_in_reward=$( [ "$(echo "$kl_coef > 0.0" | bc)" -eq 1 ] && echo true || echo false )


python3 -m verl.trainer.main_ppo \
    algorithm.adv_estimator=${estimator} \
    data.train_files=${train_path} \
    data.val_files=${test_path} \
    data.train_batch_size=${train_batch_size} \
    data.max_prompt_length=${max_prompt_length} \
    data.max_response_length=${max_response_length} \
    data.filter_overlong_prompts=True \
    data.truncation='error' \
    data.use_chat_template=${use_chat_template} \
    data.under_performing_acc_lower=0.125 \
    data.under_performing_acc_upper=0.500 \
    data.positive_synthesis_acc_lower=0.125 \
    data.positive_synthesis_acc_upper=0.625 \
    actor_rollout_ref.model.path=${model_name_or_path} \
    actor_rollout_ref.actor.optim.lr=1e-6 \
    actor_rollout_ref.model.use_remove_padding=True \
    actor_rollout_ref.actor.ppo_mini_batch_size=${ppo_mini_batch_size} \
    actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=16 \
    actor_rollout_ref.actor.use_kl_loss=${use_kl_loss} \
    actor_rollout_ref.actor.kl_loss_coef=${kl_loss_coef} \
    actor_rollout_ref.actor.kl_loss_type=low_var_kl \
    actor_rollout_ref.actor.entropy_coeff=0 \
    actor_rollout_ref.actor.ppo_max_token_len_per_gpu=${ppo_max_token_len_per_gpu} \
    actor_rollout_ref.actor.use_dynamic_bsz=${use_dynamic_bsz} \
    actor_rollout_ref.model.enable_gradient_checkpointing=True \
    actor_rollout_ref.actor.fsdp_config.param_offload=False \
    actor_rollout_ref.actor.fsdp_config.optimizer_offload=False \
    actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=$((log_prob_micro_batch_size_per_gpu * 2)) \
    actor_rollout_ref.rollout.tensor_model_parallel_size=${tensor_model_parallel_size} \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.8 \
    actor_rollout_ref.rollout.n=${n_samples} \
    actor_rollout_ref.rollout.use_tqdm=${use_tqdm} \
    actor_rollout_ref.rollout.max_num_batched_tokens=${ppo_max_token_len_per_gpu} \
    actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=$((log_prob_micro_batch_size_per_gpu * 2)) \
    actor_rollout_ref.ref.fsdp_config.param_offload=True \
    algorithm.use_kl_in_reward=${use_kl_in_reward} \
    trainer.critic_warmup=0 \
    trainer.experiment_name=${experiment_name} \
    trainer.n_gpus_per_node=1 \
    trainer.nnodes=${NUM_GPUS} \
    trainer.save_freq=${save_freq} \
    trainer.test_freq=${test_freq}  \
    trainer.total_epochs=${total_epochs} \
    trainer.val_before_train=${val_before_train} \
    trainer.default_local_dir=${save_path} \
    trainer.task='svs' $@ # set the task to 'rl' or 'svs'