#!/usr/bin/env bash
# install-all.sh
# Sets up Ollama + multiple models + Open WebUI
# Supports both ARM64 (Raspberry Pi) and x86_64 (desktop/server)
# Enables local network access for VS Code / browser
# Basic firewall hardening (ufw)

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
#  Usage / flag parsing
# ────────────────────────────────────────────────────────────────────────────────

TARGET_ARCH=""
GPU_FLAG=""   # "", "force", or "disable"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --arm         Target ARM64 architecture (Raspberry Pi / aarch64)
  --x86         Target x86_64 architecture (desktop / server)
  --gpu         Force-enable NVIDIA GPU passthrough for Docker containers
  --no-gpu      Disable GPU passthrough even if a GPU is detected
  -h, --help    Show this help message

If no architecture flag is given, the script auto-detects from the host.
If neither --gpu nor --no-gpu is given, the script auto-detects NVIDIA GPUs.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arm)    TARGET_ARCH="arm64"; shift ;;
        --x86)    TARGET_ARCH="x86_64"; shift ;;
        --gpu)    GPU_FLAG="force"; shift ;;
        --no-gpu) GPU_FLAG="disable"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ────────────────────────────────────────────────────────────────────────────────
#  Configuration
# ────────────────────────────────────────────────────────────────────────────────

# Models to pull — add or remove entries to taste
MODELS=(
    "qwen2.5-coder:7b"        # Code assistant — autocomplete, generation & refactoring
    "llava:7b"                 # Visual assistant — image understanding & description
    "qwen2.5:7b"              # General assistant — chat, summarisation & reasoning
)

OLLAMA_PORT="11434"
WEBUI_PORT="8080"                  # Open WebUI web interface
HOST="0.0.0.0"                     # Listen on all interfaces (LAN access)

# Change these if you want stricter firewall rules
ALLOW_FROM="192.168.0.0/16"        # Typical home LAN; change to your subnet e.g. 192.168.1.0/24 or 10.0.0.0/8

# ────────────────────────────────────────────────────────────────────────────────
#  Helper functions
# ────────────────────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

check_command() {
    command -v "$1" >/dev/null 2>&1 || error "$1 is required but not installed."
}

# ────────────────────────────────────────────────────────────────────────────────
#  1. System checks & updates
# ────────────────────────────────────────────────────────────────────────────────

info "Updating system & checking architecture..."
sudo apt update -yqq && sudo apt upgrade -yqq
sudo apt install -y curl git ufw

ARCH=$(uname -m)

# Auto-detect if no flag was given
if [[ -z "$TARGET_ARCH" ]]; then
    case "$ARCH" in
        aarch64|arm64) TARGET_ARCH="arm64" ;;
        x86_64)        TARGET_ARCH="x86_64" ;;
        *) error "Unsupported architecture: $ARCH. Use --arm or --x86 to override." ;;
    esac
    info "Auto-detected architecture: ${TARGET_ARCH}"
else
    info "Architecture override: ${TARGET_ARCH} (host is ${ARCH})"
fi

# ── GPU detection ──
USE_GPU=false

if [[ "$GPU_FLAG" == "force" ]]; then
    USE_GPU=true
    info "GPU passthrough force-enabled via --gpu flag."
elif [[ "$GPU_FLAG" == "disable" ]]; then
    USE_GPU=false
    info "GPU passthrough disabled via --no-gpu flag."
else
    # Auto-detect: look for NVIDIA GPU + nvidia-smi or lspci
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        USE_GPU=true
        info "Auto-detected NVIDIA GPU (nvidia-smi)."
    elif lspci 2>/dev/null | grep -iq nvidia; then
        USE_GPU=true
        info "Auto-detected NVIDIA GPU (lspci). Ensure nvidia-container-toolkit is installed."
    else
        info "No NVIDIA GPU detected — running in CPU-only mode."
    fi
fi

if [[ "$USE_GPU" == true && "$TARGET_ARCH" == "arm64" ]]; then
    info "Warning: GPU passthrough is not common on ARM64. Proceeding anyway."
fi

# ────────────────────────────────────────────────────────────────────────────────
#  2. Install Ollama
# ────────────────────────────────────────────────────────────────────────────────

info "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

sleep 4

# Configure Ollama for network access
info "Configuring Ollama to listen on all interfaces..."

sudo mkdir -p /etc/systemd/system/ollama.service.d

cat << 'END_CONF' | sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
# Optional - limit if RAM is tight on Pi
# Environment="OLLAMA_MAX_LOADED_MODELS=1"
END_CONF

sudo systemctl daemon-reload
sudo systemctl restart ollama
sleep 5

# Quick test
if curl -s http://localhost:11434 >/dev/null; then
    info "Ollama API is now listening on port 11434 (network access enabled)."
else
    error "Ollama failed to start or is not listening. Check: journalctl -u ollama -n 50"
fi

# ────────────────────────────────────────────────────────────────────────────────
#  3. Pull models
# ────────────────────────────────────────────────────────────────────────────────

for model in "${MODELS[@]}"; do
    info "Pulling model: ${model} ..."
    ollama pull "${model}"

    info "Verifying model: ${model}"
    ollama list | grep -q "${model%%:*}" || error "Model pull failed for ${model}."
done

# Warm up the first model (loads it into RAM)
info "Pre-loading ${MODELS[0]} ..."
ollama run "${MODELS[0]}" "Model loaded — ready." >/dev/null 2>&1 &

# ────────────────────────────────────────────────────────────────────────────────
#  4. Install Docker → Open WebUI
# ────────────────────────────────────────────────────────────────────────────────

info "Installing Docker (required for Open WebUI)..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # log out & back in after script finishes

info "Launching Open WebUI (ChatGPT-like interface)..."

DOCKER_ARGS=(run -d --network=host
  -v open-webui:/app/backend/data
  -e OLLAMA_BASE_URL=http://127.0.0.1:${OLLAMA_PORT}
  --name open-webui --restart always)

if [[ "$USE_GPU" == true ]]; then
    info "Enabling NVIDIA GPU passthrough for Open WebUI container..."
    DOCKER_ARGS+=(--gpus all)
fi

DOCKER_ARGS+=(ghcr.io/open-webui/open-webui:main)

docker "${DOCKER_ARGS[@]}"

sleep 8

# ────────────────────────────────────────────────────────────────────────────────
#  5. Basic firewall hardening (ufw)
# ────────────────────────────────────────────────────────────────────────────────

info "Configuring ufw firewall (allow only local network)..."

sudo ufw allow from "${ALLOW_FROM}" to any port "${OLLAMA_PORT}" proto tcp comment "Ollama API — local network"
sudo ufw allow from "${ALLOW_FROM}" to any port "${WEBUI_PORT}"  proto tcp comment "Open WebUI — local network"
sudo ufw --force enable    # warning: this enables the firewall!

# If you're SSH'd in remotely and fear lockout — comment out the enable line above
# and run sudo ufw enable manually after testing

# ────────────────────────────────────────────────────────────────────────────────
#  6. Summary & next steps
# ────────────────────────────────────────────────────────────────────────────────

HOST_IP=$(hostname -I | awk '{print $1}')

info "──────────────────────────────────────────────────────────────"
info "Setup complete! 🎉"
info ""
info "• Architecture   → ${TARGET_ARCH}"
info "• GPU enabled    → ${USE_GPU}"
info "• Ollama API     → http://${HOST_IP}:${OLLAMA_PORT}"
info "• Open WebUI     → http://${HOST_IP}:${WEBUI_PORT}     (open in browser)"
info ""
info "Models installed:"
for model in "${MODELS[@]}"; do
    info "  • ${model}"
done
info ""
info "Open WebUI will auto-detect all Ollama models."
info "Switch between them from the model selector in the UI."
info ""
info "VS Code / Continue extension config:"
info "  apiBase: http://${HOST_IP}:${OLLAMA_PORT}"
info "  model:   ${MODELS[0]}"
info ""
info "Test commands (from another machine on LAN):"
info "  curl http://${HOST_IP}:${OLLAMA_PORT}                  # should say 'Ollama is running'"
info "  curl http://${HOST_IP}:${OLLAMA_PORT}/api/tags         # list models"
info ""
info "Security notes:"
info "  • Only LAN access allowed (ufw rules)"
info "  • For HTTPS / authentication → add Caddy / Nginx reverse proxy later"
info "  • Change ALLOW_FROM if your subnet is different"
info "──────────────────────────────────────────────────────────────"

info "Log out and back in (or reboot) so docker group takes effect."
info "Enjoy your private, local AI coding assistant!"

exit 0