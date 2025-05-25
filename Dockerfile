# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

# ------------------------------------------------------------
# Consolidated environment variables
# ------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# ------------------------------------------------------------
# System packages + Python 3.12 venv
# ------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv aria2 python3.12-dev \
        python3-pip \
        curl ffmpeg ninja-build git git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    python3.12 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:$PATH"

# ------------------------------------------------------------
# PyTorch (CUDA 12.8) & core tooling (no pip cache mounts)
# ------------------------------------------------------------
# 2) Install PyTorch (CUDA 12.8) & freeze torch versions to constraints file
RUN pip install --upgrade pip && \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    # Save exact installed torch versions
    pip freeze | grep -E "^(torch|torchvision|torchaudio)" > /tmp/torch-constraint.txt && \
    # Install core tooling
    pip install packaging setuptools wheel pyyaml gdown triton runpod opencv-python

# 3) Clone ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /ComfyUI

# 4) Install ComfyUI requirements using torch constraint file
RUN cd /ComfyUI && \
    pip install -r requirements.txt --constraint /tmp/torch-constraint.txt

# 5) Install additional required packages
RUN pip install onnxruntime-gpu insightface==0.7.3

# ------------------------------------------------------------
# Model directories setup
# ------------------------------------------------------------
RUN mkdir -p /models/checkpoints /models/upscale_models /models/vae /models/clip_vision \
    /models/ipadapter /models/controlnet/SDXL/controlnet-union-sdxl-1.0 \
    /models/loras

# ------------------------------------------------------------
# Download Hugging Face models
# ------------------------------------------------------------
# IP-Adapter models
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors && \
    aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors && \
    aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/ipadapter/ip-adapter_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors && \
    aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin \
        https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin

# CLIP Vision models
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors && \
    aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/clip_vision/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors

# LoRA model
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors \
        https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors

# ControlNet Union model
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/controlnet/SDXL/controlnet-union-sdxl-1.0/diffusion_pytorch_model_promax.safetensors \
        https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors

# ------------------------------------------------------------
# Install CivitAI Downloader
# ------------------------------------------------------------
RUN git clone https://github.com/Hearmeman24/CivitAI_Downloader.git /tmp/CivitAI_Downloader && \
    mv /tmp/CivitAI_Downloader/download_with_aria.py /usr/local/bin/ && \
    chmod +x /usr/local/bin/download_with_aria.py && \
    rm -rf /tmp/CivitAI_Downloader

# ------------------------------------------------------------
# Download Upscale models
# ------------------------------------------------------------
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/upscale_models/4xLSDIR.pth \
        https://github.com/Phhofm/models/raw/main/4xLSDIR/4xLSDIR.pth && \
    aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --out=/models/upscale_models/4xFaceUpLDAT.pth \
        https://huggingface.co/RafaG/models-ESRGAN/resolve/82caaaedb2d27e9f76472351828178b62995c2f1/4xFaceUpLDAT.pth

# ------------------------------------------------------------
# Download CivitAI models (requires CIVITAI_TOKEN build arg)
# ------------------------------------------------------------
ARG CIVITAI_TOKEN

# Download checkpoints - each in its own layer for better caching
# Layer 1: checkpoint 1081768
RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1081768 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping checkpoint 1081768 download."; \
    fi; \
} > /tmp/download.log 2>&1

# Layer 2: checkpoint 1633727
RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 378499 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping checkpoint 378499 download."; \
    fi; \
} >> /tmp/download.log 2>&1

# Layer 3: checkpoint 1609607
RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1609607 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping checkpoint 1609607 download."; \
    fi; \
} >> /tmp/download.log 2>&1

RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 403131 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping checkpoint 403131 download."; \
    fi; \
} >> /tmp/download.log 2>&1

# Layer 4: checkpoint 1041855
RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1041855 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping checkpoint 1041855 download."; \
    fi; \
} >> /tmp/download.log 2>&1

# Download LoRAs in a single layer, appending to the same log
RUN { \
    if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 135867  --token "$CIVITAI_TOKEN" -o /models/loras; \
        python /usr/local/bin/download_with_aria.py -m 128461  --token "$CIVITAI_TOKEN" -o /models/loras; \
        python /usr/local/bin/download_with_aria.py -m 703107  --token "$CIVITAI_TOKEN" -o /models/loras; \
        python /usr/local/bin/download_with_aria.py -m 283697  --token "$CIVITAI_TOKEN" -o /models/loras; \
        python /usr/local/bin/download_with_aria.py -m 127928  --token "$CIVITAI_TOKEN" -o /models/loras; \
        python /usr/local/bin/download_with_aria.py -m 1071060 --token "$CIVITAI_TOKEN" -o /models/loras; \
    else \
        echo "Warning: CIVITAI_TOKEN not provided. Skipping LoRA downloads."; \
    fi; \
} >> /tmp/download.log 2>&1

# ------------------------------------------------------------
# Final stage
# ------------------------------------------------------------
FROM base AS final
ENV PATH="/opt/venv/bin:$PATH"
RUN python -m pip install opencv-python

# Copy models from previous stage
COPY --from=base /models /models

RUN for repo in \
    https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git \
    https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
    https://github.com/Fannovel16/comfyui_controlnet_aux.git \
    https://github.com/WASasquatch/was-node-suite-comfyui.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/chflame163/ComfyUI_LayerStyle.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git \
    https://github.com/Jonseed/ComfyUI-Detail-Daemon.git \
    https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git \
    https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/M1kep/ComfyLiterals.git; \
    do \
        cd /ComfyUI/custom_nodes; \
        repo_dir=$(basename "$repo" .git); \
        if [ "$repo" = "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" ]; then \
            git clone --recursive "$repo"; \
        else \
            git clone "$repo"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" ]; then \
            pip install -r "/ComfyUI/custom_nodes/$repo_dir/requirements.txt"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/install.py" ]; then \
            python "/ComfyUI/custom_nodes/$repo_dir/install.py"; \
        fi; \
    done

COPY src/start_script.sh /start_script.sh
COPY Eyes.pt /Eyes.pt

CMD ["/start_script.sh"]