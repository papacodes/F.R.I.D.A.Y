#!/bin/bash

# Friday: Natural Voice Setup
MODEL_DIR="$HOME/Models/friday"
KOKORO_PATH="$MODEL_DIR/kokoro-v1_0"
mkdir -p "$KOKORO_PATH"

echo "--------------------------------------------------"
echo "Friday: Downloading Natural Voice (ONNX)..."
echo "--------------------------------------------------"

HF_CMD="hf"
if ! command -v hf &> /dev/null; then HF_CMD="huggingface-cli"; fi

# Download the ONNX model from the specific 'onnx' branch
$HF_CMD download hexgrad/Kokoro-82M kokoro-v0_19.onnx voices.json --revision onnx --local-dir "$KOKORO_PATH"

# Download the high-quality heart voice
$HF_CMD download hexgrad/Kokoro-82M voices/af_heart.pt --local-dir "$KOKORO_PATH"

echo "--------------------------------------------------"
echo "Weights updated! Launching Friday now will be natural."
echo "--------------------------------------------------"
