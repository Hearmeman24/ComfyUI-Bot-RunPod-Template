#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Set the network volume path
NETWORK_VOLUME="/workspace"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

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

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

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

# Download upscale model
echo "Downloading additional models"
mkdir -p "$NETWORK_VOLUME/ComfyUI/models/upscale_models"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt" \
    https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth
fi

mkdir -p "$NETWORK_VOLUME/ComfyUI/models/ultralytics/segm"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/ultralytics/segm/face_yolov8m-seg_60.pt" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/ultralytics/segm/face_yolov8m-seg_60.pt" \
    https://huggingface.co/24xx/segm/resolve/main/face_yolov8m-seg_60.pt
fi

mkdir -p "$NETWORK_VOLUME/ComfyUI/models/sams"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/sams/sam_vit_b_01ec64.pth" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/sams/sam_vit_b_01ec64.pth" \
    https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth
fi

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

echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

cd /

WORKFLOWS=("SDXL_Upscaling.json" "Basic_SDXL.json" "SDXL_LATENT_UPSCALING_V2.json" "SDXL_Consistent_Character_No_Lora.json")

for WORKFLOW in "${WORKFLOWS[@]}"; do
    if [ -f "./$WORKFLOW" ]; then
        if [ ! -f "$WORKFLOW_DIR/$WORKFLOW" ]; then
            mv "./$WORKFLOW" "$WORKFLOW_DIR"
            echo "$WORKFLOW copied."
        else
            echo "$WORKFLOW already exists in the target directory, skipping move."
        fi
    else
        echo "$WORKFLOW not found in the current directory."
    fi
done

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

if [ "$change_preview_method" == "true" ]; then
    echo "Updating default preview method..."
    CONFIG_PATH="$NETWORK_VOLUME/ComfyUI/user/default/ComfyUI-Manager"
    CONFIG_FILE="$CONFIG_PATH/config.ini"

# Ensure the directory exists
mkdir -p "$CONFIG_PATH"

# Create the config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.ini..."
    cat <<EOL > "$CONFIG_FILE"
[default]
preview_method = auto
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
skip_migration_check = False
always_lazy_install = False
network_mode = public
db_mode = cache
EOL
else
    echo "config.ini already exists. Updating preview_method..."
    sed -i 's/^preview_method = .*/preview_method = auto/' "$CONFIG_FILE"
fi
echo "Config file setup complete!"
    echo "Default preview method updated to 'auto'"
else
    echo "Skipping preview method update (change_preview_method is not 'true')."
fi

# Start ComfyUI
echo "Starting ComfyUI"
python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen
