import os
import sys
import json
import time
import torch
import random
import argparse
import numpy as np
from pdb import set_trace
from vllm import LLM, SamplingParams
from datasets import load_dataset
from transformers import AutoTokenizer
sys.path.append(os.getcwd())
from verl.utils.reward_score.prime_math import compute_score
NUM_PROC = os.cpu_count() // 4 * 3


def eval_accuracy(sample):
    '''Getting accuracy from predictions'''
    accs = []
    for pred in sample['prediction']:
        acc_compute_score = compute_score(sample['ref_answer'], pred)[0]
        print(acc_compute_score)
        acc = 1.0 if acc_compute_score else 0.0
        accs.append(acc)
    return {"acc": np.sum(accs), "if_acc": accs}


def evaluate_and_print(outputs, model_path, additional_str=""):
    # loading the dataset
    result_path = os.path.join(model_path, f"eval_math_aime{additional_str}_results.json")
    if os.path.exists(result_path):
        split_accs = json.load(open(result_path, "r"))
        print(split_accs)
        return split_accs
    
    # verify the responses and statistics the data_sources
    split_accs = {"Model": model_path.split("/")[-1]}
    outputs_verify = outputs.map(eval_accuracy, num_proc=64)
    data_sources = outputs_verify.unique('data_source')
    for data_source in sorted(data_sources):
        subset = outputs_verify.filter(lambda x:x["data_source"] in [data_source], num_proc=NUM_PROC)
        split_accs[data_source] = round(np.mean(subset['acc']) * 100 / len(outputs[0]["prediction"]), 2)
        
    # calculate the average and save the results
    split_accs['AVG'] = round(np.mean([v for k, v in split_accs.items() if k not in ['Model']]), 2)
    print(split_accs)
    json.dump(split_accs, open(result_path, "w"))
    return split_accs


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--model_name_or_path", type=str)
    parser.add_argument("--output_path", type=str)
    parser.add_argument("--input_path", type=str)
    parser.add_argument("--tensor_parallel_size", default=1, type=int, choices=[1, 2, 4, 8])
    parser.add_argument("--temperature", default=0, type=float)
    parser.add_argument("--n_sampling", default=1, type=int)
    parser.add_argument("--top_p", default=1, type=float)
    parser.add_argument("--gpu_memory_utilization", default=1.0, type=float) 
    parser.add_argument("--swap_space", default=4, type=int)
    parser.add_argument("--max_tokens", default=512, type=int)
    parser.add_argument("--max_model_len", default=32768, type=int, help="The maximum length of the model input, need to set after vLLM 0.9.1.")
    args = parser.parse_args()

    available_gpus = torch.cuda.device_count()
    sample_params = SamplingParams(temperature=args.temperature, top_p=args.top_p, n=args.n_sampling, max_tokens=args.max_tokens, stop=["<end>", "\] \] \]", "\n\n\n"])

    dataset = load_dataset("json", data_files=args.input_path, split='train').shuffle().select(range(100))
    tokenizer = AutoTokenizer.from_pretrained(args.model_name_or_path)
    dataset = dataset.map(lambda x: {"vllm_input": tokenizer.apply_chat_template([{"content": x['question'] + ". Please reason step by step, and put your final answer within \\boxed{}.", 'role': 'user'}], add_generation_prompt=True, tokenize=False)}, num_proc=64)

    ### testing inputs
    os.makedirs(os.path.dirname(args.output_path), exist_ok=True)
    test_inputs = dataset["vllm_input"][:5]
    for id in range(len(test_inputs)):
        print(f">>> Testing input {id + 1}: \n{test_inputs[id]}")
    
    ### testing outputs
    # TODO: fix the bug for vLLM loading in GCR server
    model = LLM(args.model_name_or_path, tensor_parallel_size=args.tensor_parallel_size, gpu_memory_utilization=args.gpu_memory_utilization, swap_space=args.swap_space, max_model_len=args.max_model_len)
    test_outputs = model.generate(test_inputs, sample_params)
    test_outputs = [random.choice([_.outputs[i].text for i in range(len(_.outputs))]) for _ in test_outputs]
    for id in range(len(test_inputs)):
        print(f">>> Testing Output {id + 1}: \n{test_outputs[id]}")
    
    ### start inference
    print(f">>> Starting inference...")
    outputs = model.generate(dataset["vllm_input"], sample_params)
    outputs = [[_.outputs[i].text.split("<|endoftext|>")[0] for i in range(len(_.outputs))] for _ in outputs]

    print(f">>> Finishing inference")
    dataset = dataset.add_column("prediction", outputs)
    dataset = dataset.remove_columns(["vllm_input"])
    dataset.to_json(args.output_path, num_proc = os.cpu_count() // 2)
    evaluate_and_print(dataset, args.model_name_or_path, additional_str=f"_sample_{len(dataset)}_temp_{args.temperature}_n_{args.n_sampling}")