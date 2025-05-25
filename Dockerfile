# Stage 1: base image with CUDA, Python, PyTorch, and ComfyUI code
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8 \
    PATH="/opt/venv/bin:$PATH"

# System packages and Python venv
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv aria2 python3.12-dev python3-pip \
        curl ffmpeg ninja-build git git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    python3.12 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# PyTorch (CUDA 12.8) & core tooling
RUN pip install --upgrade pip && \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    pip freeze | grep -E "^(torch|torchvision|torchaudio)" > /tmp/torch-constraint.txt && \
    pip install packaging setuptools wheel pyyaml gdown triton runpod opencv-python

# Clone ComfyUI and install requirements
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /ComfyUI && \
    cd /ComfyUI && \
    pip install -r requirements.txt --constraint /tmp/torch-constraint.txt

# Install additional Python packages
RUN pip install onnxruntime-gpu insightface==0.7.3

# Create directories for models
RUN mkdir -p /models/checkpoints /models/upscale_models /models/vae /models/clip_vision \
    /models/ipadapter /models/controlnet/SDXL/controlnet-union-sdxl-1.0 \
    /models/loras

# Install CivitAI Downloader for use in subsequent layers
RUN git clone https://github.com/Hearmeman24/CivitAI_Downloader.git /tmp/CivitAI_Downloader && \
    mv /tmp/CivitAI_Downloader/download_with_aria.py /usr/local/bin/ && \
    chmod +x /usr/local/bin/download_with_aria.py && \
    rm -rf /tmp/CivitAI_Downloader

# Copy entrypoint and assets
COPY src/start_script.sh /start_script.sh
COPY Eyes.pt /Eyes.pt

# ------------------------------------------------------------
# Stage 2: final image with models baked in separate layers
# ------------------------------------------------------------
FROM base AS final
ENV PATH="/opt/venv/bin:$PATH"

# Group 1: IP-Adapter models (~10 GB)
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --dir=/models/ipadapter \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter_sdxl_vit-h.safetensors \
        https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin

# Group 2: CLIP Vision models (~5 GB)
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --dir=/models/clip_vision \
        https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors \
        https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors

# Group 3: LoRA model (~1 GB)
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --dir=/models/loras \
        https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors

# Group 4: ControlNet Union model (~3 GB)
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --dir=/models/controlnet/SDXL/controlnet-union-sdxl-1.0 \
        https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors

# Group 5: Upscale models (~2 GB)
RUN aria2c -x 8 -s 8 --file-allocation=none --continue=true \
        --dir=/models/upscale_models \
        https://github.com/Phhofm/models/raw/main/4xLSDIR/4xLSDIR.pth \
        https://huggingface.co/RafaG/models-ESRGAN/resolve/82caaaedb2d27e9f76472351828178b62995c2f1/4xFaceUpLDAT.pth

# Group 6: CivitAI checkpoints (one per layer, ~couple GB each)
ARG CIVITAI_TOKEN
RUN if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1081768 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    fi
RUN if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 378499 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    fi
RUN if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1609607 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    fi
RUN if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 403131 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    fi
RUN if [ -n "$CIVITAI_TOKEN" ]; then \
        python /usr/local/bin/download_with_aria.py -m 1041855 --token "$CIVITAI_TOKEN" -o /models/checkpoints; \
    fi

# Clone custom ComfyUI nodes & install their requirements
RUN cd /ComfyUI/custom_nodes && \
    for repo in \
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
        git clone --depth 1 "$repo"; \
        name=$(basename "$repo" .git); \
        if [ -f "/ComfyUI/custom_nodes/$name/requirements.txt" ]; then pip install -r "/ComfyUI/custom_nodes/$name/requirements.txt"; fi; \
        if [ -f "/ComfyUI/custom_nodes/$name/install.py" ]; then python "/ComfyUI/custom_nodes/$name/install.py"; fi; \
    done

# Final command\
COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh
CMD ["/start_script.sh"]