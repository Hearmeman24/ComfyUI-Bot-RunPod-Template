#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Set the network volume path
NETWORK_VOLUME="/workspace"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

if [ ! -d "comfyui-discord-bot" ]; then
  git clone https://${GITHUB_PAT}@github.com/Hearmeman24/comfyui-discord-bot.git
  cd /comfyui-discord-bot
  mv Potrait01.png /ComfyUI/input
  pip install -r requirements.txt
  cd /
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"

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

declare -A MODEL_CATEGORIES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="$CHECKPOINT_IDS_TO_DOWNLOAD"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="$LORAS_IDS_TO_DOWNLOAD"
)

# Ensure directories exist and download models
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    mkdir -p "$TARGET_DIR"
    IFS=',' read -ra MODEL_IDS <<< "${MODEL_CATEGORIES[$TARGET_DIR]}"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        echo "Downloading model: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download.py --model "$MODEL_ID")
    done
done

echo "All models downloaded successfully!"

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

echo "Starting worker"
nohup python3 "$NETWORK_VOLUME"/comfyui-discord-bot/worker.py > "$NETWORK_VOLUME"/worker.log 2>&1 &

echo "Starting ComfyUI"
python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen
