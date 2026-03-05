#!/usr/bin/env python3
import sys
import argparse
import numpy as np
import soundfile as sf
import os
from pathlib import Path

# This script assumes 'kokoro-onnx' is installed via pip: pip install kokoro-onnx soundfile
try:
    from kokoro_onnx import Kokoro
except ImportError:
    print("ERROR: kokoro_onnx is not installed. Run: pip install kokoro-onnx soundfile", file=sys.stderr)
    sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Friday Kokoro ONNX Bridge")
    parser.add_argument("--text", type=str, required=True, help="Text to speak")
    parser.add_argument("--voice", type=str, default="af_heart", help="Voice name")
    parser.add_argument("--output", type=str, default="output.wav", help="Output WAV path")
    args = parser.parse_args()

    model_dir = Path.home() / "Models" / "friday" / "kokoro-v1_0"
    onnx_path = model_dir / "kokoro-v1.0.onnx"
    voices_path = model_dir / "voices-v1.0.bin"

    if not onnx_path.exists():
        print(f"ERROR: Model not found at {onnx_path}", file=sys.stderr)
        sys.exit(1)

    if not voices_path.exists():
        print(f"ERROR: voices-v1.0.bin not found at {voices_path}", file=sys.stderr)
        sys.exit(1)

    try:
        # Initialize Kokoro with official files
        kokoro = Kokoro(str(onnx_path), str(voices_path))
        
        # Verify requested voice exists, fallback to af_bella if af_heart missing
        if args.voice not in kokoro.get_voices():
            print(f"WARNING: Voice {args.voice} not found. Falling back to af_bella.", file=sys.stderr)
            voice = "af_bella"
        else:
            voice = args.voice
            
        samples, sample_rate = kokoro.create(
            args.text, 
            voice=voice, 
            speed=1.0, 
            lang="en-us"
        )
        sf.write(args.output, samples, sample_rate)
        print(f"SUCCESS: {args.output}")
    except Exception as e:
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
