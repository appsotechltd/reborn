#!/usr/bin/env bash
# Installs the free Kokoro voice: a Python venv with kokoro-onnx plus the
# Kokoro-82M model files (about 350 MB) in .cache/kokoro.
set -euo pipefail
cd "$(dirname "$0")/.."
dir=.cache/kokoro
mkdir -p "$dir"
python3 -m venv "$dir/venv"
"$dir/venv/bin/pip" install --quiet "kokoro-onnx==0.6.1" soundfile
base=https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  [ -f "$dir/$f" ] || curl -fL --retry 3 -o "$dir/$f" "$base/$f"
done
echo "Kokoro ready in $dir"
