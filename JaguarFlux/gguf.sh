#!/bin/bash

# This file will be sourced in init.sh
# https://github.com/MushroomFleet/Runpod-init

set -euo pipefail

### ────────────────────────────────────────────────────────────────────
### 0) REQUIRED ENV VARS
### ────────────────────────────────────────────────────────────────────
# Make sure you’ve exported HF_TOKEN in your RunPod env vars
if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "ERROR: You must export HF_TOKEN before running provisioning." >&2
  exit 1
fi

# Point WORKSPACE at /opt so that models land in /opt/ComfyUI/models/…
export WORKSPACE="/opt"

### ────────────────────────────────────────────────────────────────────
### 1) YOUR MODEL / NODE / WORKFLOW LISTS (unchanged)
### ────────────────────────────────────────────────────────────────────
DEFAULT_WORKFLOW="https://raw.githubusercontent.com/ai-dock/comfyui/main/config/workflows/flux-comfyui-example.json"

APT_PACKAGES=(
    #"package-1"
)

PIP_PACKAGES=(
    #"package-1"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
    # …etc…
)

WORKFLOWS=(
    "https://github.com/MushroomFleet/DJZ-Workflows"
)

CHECKPOINT_MODELS=(
    #…"your URLs"…
)

UNET_MODELS=(
    #…"your URLs"…
)

DIFFUSION_MODELS=(
    "https://huggingface.co/shuttleai/shuttle-jaguar/resolve/main/gguf/shuttle-jaguar-Q8_0.gguf"
    "https://huggingface.co/YarvixPA/FLUX.1-Fill-dev-gguf/resolve/main/flux1-fill-dev-Q8_0.gguf"
)

CLIP_MODELS=(
    "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/clip_l.safetensors"
    "https://huggingface.co/camenduru/FLUX.1-dev/resolve/main/t5xxl_fp16.safetensors"
)

LORA_MODELS=(
    "https://huggingface.co/mushroomfleet/Flux-Lora-Collection/resolve/main/AssassinKahb-8-16-e9-10.safetensors"
    "https://huggingface.co/mushroomfleet/Flux-Lora-Collection/resolve/main/AssassinKahb-flux-1024x-Kappa-Prodigy-e12.safetensors"
    "https://huggingface.co/coregitedge/model1lora/resolve/main/model1lora-000009.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors"
)

ESRGAN_MODELS=(
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
)

CONTROLNET_MODELS=(
    "https://huggingface.co/XLabs-AI/flux-controlnet-collections/resolve/main/flux-hed-controlnet-v3.safetensors"
    "https://huggingface.co/XLabs-AI/flux-controlnet-collections/resolve/main/flux-canny-controlnet-v3.safetensors"
    "https://huggingface.co/XLabs-AI/flux-controlnet-collections/resolve/main/flux-depth-controlnet-v3.safetensors"
)

### ────────────────────────────────────────────────────────────────────
### 2) INTERNAL FUNCTIONS (mostly unchanged)
### ────────────────────────────────────────────────────────────────────
function pip_install() {
    if [[ -z "${MAMBA_BASE:-}" ]]; then
        "$COMFYUI_VENV_PIP" install --no-cache-dir "$@"
    else
        micromamba run -n comfyui pip install --no-cache-dir "$@"
    fi
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
      -H "Authorization: Bearer $HF_TOKEN" \
      https://huggingface.co/api/whoami-v2)
    [[ "$code" -eq 200 ]]
}

function provisioning_download() {
    local url="$1" dest="$2" auth=""
    if [[ "$url" =~ huggingface\.co && -n "$HF_TOKEN" ]]; then
        auth="--header=Authorization: Bearer $HF_TOKEN"
    fi
    mkdir -p "$dest"
    wget $auth --content-disposition --show-progress -nc -P "$dest" "$url"
}

function provisioning_get_models() {
    local dir="$1"; shift
    echo "→ Downloading ${#@} model(s) into $dir"
    for url in "$@"; do
        echo "   - $url"
        provisioning_download "$url" "$dir"
    done
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        local name="${repo##*/}"
        local path="/opt/ComfyUI/custom_nodes/$name"
        if [[ -d "$path" ]]; then
            echo "Updating $name..."
            (cd "$path" && git pull)
        else
            echo "Cloning $name..."
            git clone "$repo" "$path" --recursive
        fi
        [[ -f "$path/requirements.txt" ]] && pip_install -r "$path/requirements.txt"
    done
}

function provisioning_get_workflows() {
    for repo in "${WORKFLOWS[@]}"; do
        local name=$(basename "$repo" .git)
        local path="/opt/ComfyUI/user/default/workflows/$name"
        if [[ -d "$path" ]]; then
            echo "Updating workflow $name..."
            (cd "$path" && git pull)
        else
            echo "Cloning workflow $name..."
            git clone "$repo" "$path"
        fi
    done
}

### ────────────────────────────────────────────────────────────────────
### 3) MAIN: replace old provisioning_start with this
### ────────────────────────────────────────────────────────────────────
function provisioning_start() {
    echo "===== Starting ComfyUI provisioning ====="
    if [[ ! -d /opt/environments/python ]]; then 
        export MAMBA_BASE=true
    fi
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh comfyui

    provisioning_get_nodes
    pip_install "${PIP_PACKAGES[@]}"

    # download into the real ComfyUI model folders under /opt
    provisioning_get_models "/opt/ComfyUI/models/ckpt"            "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/unet"           "${UNET_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/clip"           "${CLIP_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/loras"          "${LORA_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/vae"            "${VAE_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/esrgan"         "${ESRGAN_MODELS[@]}"
    provisioning_get_models "/opt/ComfyUI/models/controlnet"     "${CONTROLNET_MODELS[@]}"

    provisioning_get_workflows

    echo "✅ Provisioning complete. Starting Web UI…"
}

provisioning_start
