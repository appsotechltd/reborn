#!/usr/bin/env bash
# Installs the Chatterbox voice (MIT licence): a Python venv with chatterbox-tts in
# .cache/chatterbox. Its model files download from huggingface.co on first use,
# so that host must be allowed in the environment's network settings. PyTorch makes
# this a large install (several GB).
set -euo pipefail
cd "$(dirname "$0")/.."
dir=.cache/chatterbox
mkdir -p "$dir"
python3 -m venv "$dir/venv"
"$dir/venv/bin/pip" install --quiet "chatterbox-tts==0.1.7"
echo "Chatterbox ready in $dir (models download on first use)"
