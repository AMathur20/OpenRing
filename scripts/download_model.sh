#!/usr/bin/env bash
# ==============================================================================
# OpenRing - Llama 3.2 3B Instruct GGUF Model Downloader
# ==============================================================================
# Downloads the 4-bit quantized Llama-3.2-3B-Instruct model (Q4_K_M)
# for local-first, zero-telemetry on-device inference via llama.cpp.
#
# Target File: Models/Llama-3.2-3B-Instruct-Q4_K_M.gguf (~2.02 GB)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/Models"
TARGET_FILE="${TARGET_DIR}/Llama-3.2-3B-Instruct-Q4_K_M.gguf"

# Hugging Face Direct Download URL
MODEL_URL="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"

echo "=========================================================="
echo "  OpenRing Edge AI: Llama-3.2-3B Model Downloader        "
echo "=========================================================="

mkdir -p "${TARGET_DIR}"

if [[ -f "${TARGET_FILE}" ]]; then
    FILE_SIZE=$(stat -f%z "${TARGET_FILE}" 2>/dev/null || stat -c%s "${TARGET_FILE}" 2>/dev/null || echo "0")
    if [[ "${FILE_SIZE}" -gt 1500000000 ]]; then
        echo "✅ Model already exists at: ${TARGET_FILE}"
        echo "   Size: $((FILE_SIZE / 1024 / 1024)) MB"
        exit 0
    else
        echo "⚠️ Incomplete model file detected (${FILE_SIZE} bytes). Resuming download..."
    fi
fi

echo "Downloading Llama-3.2-3B-Instruct-Q4_K_M.gguf (~2.02 GB)..."
echo "Target: ${TARGET_FILE}"
echo ""

if command -v curl >/dev/null 2>&1; then
    curl -L -C - --progress-bar "${MODEL_URL}" -o "${TARGET_FILE}"
elif command -v wget >/dev/null 2>&1; then
    wget -c "${MODEL_URL}" -O "${TARGET_FILE}"
else
    echo "❌ Error: Neither curl nor wget was found on your system."
    exit 1
fi

echo ""
echo "=========================================================="
FILE_SIZE=$(stat -f%z "${TARGET_FILE}" 2>/dev/null || stat -c%s "${TARGET_FILE}" 2>/dev/null || echo "0")
echo "✅ Download complete! Model saved to: ${TARGET_FILE}"
echo "   Size: $((FILE_SIZE / 1024 / 1024)) MB"
echo "   Ready for local-first Metal GPU inference in OpenRing."
echo "=========================================================="

