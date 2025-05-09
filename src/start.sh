#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

set -eo pipefail
set +u

if [[ "${IS_DEV,,}" =~ ^(true|1|t|yes)$ ]]; then
    API_URL="https://comfyui-job-api-dev.fly.dev"  # Replace with your development API URL
    echo "Using development API endpoint"
else
    API_URL="https://comfyui-job-api-prod.fly.dev"  # Replace with your production API URL
    echo "Using production API endpoint"
fi

URL="http://127.0.0.1:8188"

# Function to report pod status
  report_status() {
    local status=$1
    local details=$2

    echo "Reporting status: $details"

    curl -X POST "${API_URL}/pods/$RUNPOD_POD_ID/status" \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${API_KEY}" \
      -d "{\"initialized\": $status, \"details\": \"$details\"}" \
      --silent

    echo "Status reported: $status - $details"
}

report_status false "Starting initialization"
pip install insightface==0.7.3
if [ -d "/workspace" ]; then
    NETWORK_VOLUME="/workspace"
# If not, check if /runpod-volume exists
elif [ -d "/runpod-volume" ]; then
    NETWORK_VOLUME="/runpod-volume"
# Fallback to root if neither directory exists
else
    echo "Warning: Neither /workspace nor /runpod-volume exists, falling back to root directory"
    NETWORK_VOLUME="/"
fi

echo "Using NETWORK_VOLUME: $NETWORK_VOLUME"
pip install runpod
FLAG_FILE="$NETWORK_VOLUME/.comfyui_initialized"
COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
if [ "${IS_DEV:-false}" = "true" ]; then
    REPO_DIR="$NETWORK_VOLUME/comfyui-discord-bot-dev"
    BRANCH="dev"
  else
    REPO_DIR="$NETWORK_VOLUME/comfyui-discord-bot-master"
    BRANCH="master"
fi

sync_bot_repo() {
  echo "Syncing bot repo (branch: $BRANCH)..."

  if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning '$BRANCH' into $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --branch "$BRANCH" \
      "https://${GITHUB_PAT}@github.com/Hearmeman24/comfyui-discord-bot.git" \
      "$REPO_DIR"
    echo "Clone complete"

    echo "Installing Python deps..."
    cd "$REPO_DIR"
    # Add pip requirements installation here if needed
    cd /
  else
    echo "Updating existing repo in $REPO_DIR"
    cd "$REPO_DIR"

    # Clean up any Python cache files first
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    # Remove specific problematic files if they're tracked in git
    git rm --cached __pycache__/config.cpython-310.pyc 2>/dev/null || true

    # Then proceed with git operations
    git fetch origin
    git checkout "$BRANCH"

    # Try pull, if it fails do hard reset
    git pull origin "$BRANCH" || {
      echo "Pull failed, using force reset"
      git fetch origin "$BRANCH"
      git reset --hard "origin/$BRANCH"
    }

    cd /
  fi
}

if [ -f "$FLAG_FILE" ]; then
  echo "FLAG FILE FOUND"

  sync_bot_repo

  echo "▶️  Starting ComfyUI"
  # group both the main and fallback commands so they share the same log
  mkdir -p "$NETWORK_VOLUME/${RUNPOD_POD_ID}"
  nohup bash -c "python3 \"$NETWORK_VOLUME\"/ComfyUI/main.py --listen 2>&1 | tee \"$NETWORK_VOLUME\"/comfyui_\"$RUNPOD_POD_ID\"_nohup.log" &

  until curl --silent --fail "$URL" --output /dev/null; do
      echo "🔄  Still waiting…"
      sleep 2
  done

  echo "ComfyUI is UP Starting worker"
  nohup bash -c "python3 \"$REPO_DIR\"/worker.py 2>&1 | tee \"$NETWORK_VOLUME\"/\"$RUNPOD_POD_ID\"/worker.log" &

  report_status true "Pod fully initialized and ready for processing"
  echo "Initialization complete! Pod is ready to process jobs."

  # Wait on background jobs forever
  wait

else
  echo "NO FLAG FILE FOUND – starting initial setup"
fi

sync_bot_repo


if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install huggingface_hub
pip install onnxruntime-gpu

if [ "$download_faceid" == "true" ]; then
  # Define target directories
  IPADAPTER_DIR="$NETWORK_VOLUME/ComfyUI/models/ipadapter"
  CLIPVISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"

  # Create directories if they don't exist
  mkdir -p "$IPADAPTER_DIR"
  mkdir -p "$CLIPVISION_DIR"

  # Declare an associative array for IP-Adapter files
  declare -A IPADAPTER_FILES=(
      ["ip-adapter-plus-face_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"
      ["ip-adapter-plus_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"
      ["ip-adapter_sdxl_vit-h.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors"
      ["ip-adapter-faceid-plusv2_sdxl.bin"]="https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin"
  )

  # Declare an associative array for CLIP Vision files
  declare -A CLIPVISION_FILES=(
      ["CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"
      ["CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"]="https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors"
  )

  # Function to download files
  download_files() {
      local TARGET_DIR=$1
      declare -n FILES=$2  # Reference the associative array

      for FILE in "${!FILES[@]}"; do
          FILE_PATH="$TARGET_DIR/$FILE"
          if [ ! -f "$FILE_PATH" ]; then
              wget -O "$FILE_PATH" "${FILES[$FILE]}"
          else
              echo "$FILE already exists, skipping download."
          fi
      done
  }
download_files "$IPADAPTER_DIR" IPADAPTER_FILES
download_files "$CLIPVISION_DIR" CLIPVISION_FILES
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors" \
    https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors
fi
fi

if [ "$download_union_control_net" == "true" ]; then
  mkdir -p "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0"
  if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0" ]; then
      wget -O "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors" \
      https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors
  fi
fi

if [ "$download_union_control_net" == "true" ]; then
  mkdir -p "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0"
  if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors" ]; then
      wget -O "$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors" \
      https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors
  fi
fi

# Download upscale model
echo "Downloading additional models"

mkdir -p "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/Eyes.pt" ]; then
    if [ -f "/Eyes.pt" ]; then
        mv "/Eyes.pt" "$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox/Eyes.pt"
        echo "Moved Eyes.pt to the correct location."
    else
        echo "Eyes.pt not found in the root directory."
    fi
else
    echo "Eyes.pt already exists. Skipping."
fi
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth" ]; then
    if [ -f "/4xLSDIR.pth" ]; then
        mv "/4xLSDIR.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth"
        echo "Moved 4xLSDIR.pth to the correct location."
    else
        echo "4xLSDIR.pth not found in the root directory."
    fi
else
    echo "4xLSDIR.pth already exists. Skipping."
fi
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xFaceUpDAT.pth" ]; then
    if [ -f "/4xFaceUpDAT.pth" ]; then
        mv "/4xFaceUpDAT.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xFaceUpDAT.pth"
        echo "Moved 4xFaceUpDAT.pth to the correct location."
    else
        echo "4xFaceUpDAT.pth not found in the root directory."
    fi
else
    echo "4xFaceUpDAT.pth already exists. Skipping."
fi

echo "Finished downloading models!"

declare -A MODEL_CATEGORY_FILES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="$REPO_DIR/downloads/checkpoint_to_download.txt"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="$REPO_DIR/comfyui-discord-bot/downloads/image_lora_to_download.txt"
)

# Ensure directories exist and download models
for TARGET_DIR in "${!MODEL_CATEGORY_FILES[@]}"; do
    CONFIG_FILE="${MODEL_CATEGORY_FILES[$TARGET_DIR]}"

    # Skip if the file doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Skipping downloads for $TARGET_DIR (file $CONFIG_FILE not found)"
        continue
    fi

    # Read comma-separated model IDs from the file
    MODEL_IDS_STRING=$(cat "$CONFIG_FILE")

    # Skip if the file is empty or contains placeholder text
    if [ -z "$MODEL_IDS_STRING" ] || [ "$MODEL_IDS_STRING" == "replace_with_ids" ]; then
        echo "Skipping downloads for $TARGET_DIR ($CONFIG_FILE is empty or contains placeholder)"
        continue
    fi

    mkdir -p "$TARGET_DIR"
    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        echo "Downloading model: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download.py --model "$MODEL_ID") || {
            echo "ERROR: Failed to download model $MODEL_ID to $TARGET_DIR, continuing with next model..."
        }
    done
done


echo "All models downloaded successfully!"

echo "Starting ComfyUI"
touch "$FLAG_FILE"
mkdir -p "$NETWORK_VOLUME/${RUNPOD_POD_ID}"
nohup bash -c "python3 \"$NETWORK_VOLUME\"/ComfyUI/main.py --listen 2>&1 | tee \"$NETWORK_VOLUME\"/comfyui_\"$RUNPOD_POD_ID\"_nohup.log" &
COMFY_PID=$!

until curl --silent --fail "$URL" --output /dev/null; do
    echo "🔄  Still waiting…"
    sleep 2
done

echo "ComfyUI is UP Starting worker"
nohup bash -c "python3 \"$REPO_DIR\"/worker.py 2>&1 | tee \"$NETWORK_VOLUME\"/\"$RUNPOD_POD_ID\"/worker.log" &
WORKER_PID=$!

report_status true "Pod fully initialized and ready for processing"
echo "Initialization complete! Pod is ready to process jobs."
# Wait for both processes
wait $COMFY_PID $WORKER_PID
