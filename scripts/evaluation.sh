model_name_or_path=/path/to/your_model
data_path=data/MATH-AIME-Evaluation.jsonl
temperature=1.0
max_tokens=2048
num_gpus=1

python eval/math_evaluation.py \
    --model_name_or_path ${model_name_or_path} \
    --input_path ${data_path} \
    --output_path ${model_path}/MATH-AIME-Evaluation-Results.jsonl \
    --gpu_memory_utilization 0.9 \
    --top_p 0.95 \
    --temperature ${temperature} \
    --n_sampling 1 \
    --tensor_parallel_size ${num_gpus} \
    --max_tokens ${max_tokens}  \
    --swap_space 64 