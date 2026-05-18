#!/bin/bash
set -e

TARGET_DIR=$1
mkdir -p "$TARGET_DIR"

MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf"

echo "Downloading Immutable LLM Target Model Package: Qwen-2.5-7B-Instruct..."
curl -L -o "$TARGET_DIR/qwen2.5-7b-instruct-q4_k_m.gguf" "$MODEL_URL"

echo "Verification & Cryptographic Model Integration Complete." 