#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${TENSOR_EQS_MCTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
EXPERIMENTS_DIR="$REPO_ROOT/experiments"

# Settings
mode="optimize" # Mode to run, can be verify, optimize, test, convert
rules="$SCRIPT_DIR/converted.txt" # Provide a file with rewrite rules
multi_rules_default="$SCRIPT_DIR/converted_multi.txt" # Default file with multi-pattern rules. Every two lines belong to one multi-pattern rule
multi_rules_nasrnn="$SCRIPT_DIR/converted_multi_nasrnn.txt" # Multi-pattern rules file for NASRNN
out_file="stats.txt" # Provide a output file name. For mode convert, it's for converted rules; for mode optimize, it's for measured runtime
save_graph="io" # all, io, none
extract="ilp" # greedy, egg_ilp, ilp

n_iter=10000 # iter_limit: Max number of iterations for egg to run
n_sec=3600 # time_limit: Max number of seconds for egg to run
n_nodes=4000 # n_nodes: Max number of nodes for egraph
ilp_time_sec=600 # Time limit for ILP solver (0 = no limit)
ilp_num_threads=1 # Number of threads for ILP solver
node_multi=2000 # Max number of nodes added by multi-pattern rules

# Booleans
# true
export_models=" --export_models" # Whether or not to store input and optimized model
use_multi=" --use_multi" # Set this flag will enable use of multi-pattern rules
no_order=" --no_order" # No ordering constraints in ILP
all_weight_only=" --all_weight_only" # Treat zero cost for all weight concat only
no_cycle=" --no_cycle" # Not allowing cycles in EGraph
# false
order_var_int="" # Set this flag will let ILP use integer var for ordering
class_constraint="" # Add constraint in ILP that each eclass sum to 1
initial_with_greedy="" # Initialize ILP with greedy solution
filter_before="" # Filter cycles before applying rules
saturation_only="" # Run saturation only

num_passes=5

# Neural network architectures
models=(
    squeezenet
)

# k_multi settings for each model
declare -A models_iter_multi=(
    ["inceptionv3"]=2
    ["resnext50"]=4
    ["bert"]=1
    ["nasneta"]=1
    ["squeezenet"]=3
    ["vgg"]=1
    ["mobilenetv2"]=1
    ["resnet50"]=4
    ["nasrnn"]=3
)

# export TASO_GPU_WARMUP=0
# set -e

best_runtime=""
best_trial=""

for pass in $(seq 0 $(expr $num_passes - 1)); do
    for model in "${models[@]}"; do
        trial_num=$((pass + 1))
        iter_multi=${models_iter_multi[$model]}
        if [ "$model" == "nasrnn" ]; then
            multi_rules=$multi_rules_nasrnn
        else
            multi_rules=$multi_rules_default
        fi

        printf '\n=== Trial %d/%d | model=%s | iter_multi=%s ===\n' "$trial_num" "$num_passes" "$model" "$iter_multi"

        tmp_output=$(mktemp)
        set +e
        RUSTFLAGS="${RUSTFLAGS:-} -Awarnings" cargo run --quiet --release -- --iter_multi $iter_multi --model $model --mode $mode --rules "$rules" --multi_rules "$multi_rules" --out_file $out_file -s $save_graph --n_iter $n_iter --n_sec $n_sec --n_nodes $n_nodes --ilp_time_sec $ilp_time_sec --extract $extract --ilp_num_threads $ilp_num_threads --node_multi $node_multi --output_dir "$EXPERIMENTS_DIR/tensat/${model}_${iter_multi}_${pass}" $export_models$use_multi$no_order$all_weight_only$no_cycle$order_var_int$class_constraint$initial_with_greedy$filter_before$saturation_only 2>&1 | tee "$tmp_output"
        status=${PIPESTATUS[0]}
        set -e
        if [ "$status" -ne 0 ]; then
            rm -f "$tmp_output"
            exit "$status"
        fi

        current_runtime=$(awk '/Extracted graph runtime:/ { value = $4 } END { print value }' "$tmp_output")
        rm -f "$tmp_output"
        if [ -n "$current_runtime" ]; then
            if [ -z "$best_runtime" ] || awk "BEGIN { exit !($current_runtime < $best_runtime) }"; then
                best_runtime=$current_runtime
                best_trial=$trial_num
            fi

            printf 'Summary: trial %d current=%s best_so_far=%s (trial %s)\n' "$trial_num" "$current_runtime" "$best_runtime" "$best_trial"
        else
            printf 'Summary: trial %d current=unknown best_so_far=%s\n' "$trial_num" "${best_runtime:-unknown}"
        fi
    done
done
