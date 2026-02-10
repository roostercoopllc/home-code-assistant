#!/usr/bin/env bash
# install-ollama-qwen-coder-openwebui-pi.sh
# Sets up Ollama + qwen2.5-coder:7b + Open WebUI on Raspberry Pi
# Enables local network access for VS Code / browser
# Basic firewall hardening (ufw)

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
#  Configuration
# ────────────────────────────────────────────────────────────────────────────────

MODEL="qwen2.5-coder:7b"           # Best 7B coding model for autocomplete & generation
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
[[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] || error "Script designed for 64-bit ARM (aarch64). Found: $ARCH"

# ────────────────────────────────────────────────────────────────────────────────
#  2. Install Ollama
# ────────────────────────────────────────────────────────────────────────────────

info "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

sleep 4

# Configure Ollama for network access
info "Configuring Ollama to listen on ${HOST}:${OLLAMA_PORT}..."
sudo systemctl edit ollama.service << EOF
[Service]
Environment="OLLAMA_HOST=${HOST}:${OLLAMA_PORT}"
Environment="OLLAMA_ORIGINS=*"
# Optional: limit loaded models if RAM is tight
# Environment="OLLAMA_MAX_LOADED_MODELS=1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama
sleep 6

# ────────────────────────────────────────────────────────────────────────────────
#  3. Pull best coding model
# ────────────────────────────────────────────────────────────────────────────────

info "Pulling model: ${MODEL} (this may take 5–15 minutes)..."
ollama pull "${MODEL}"

info "Verifying model..."
ollama list | grep -q "${MODEL%%:*}" || error "Model pull failed."

# Optional: warm up the model (loads it into RAM)
info "Pre-loading model (may take a few minutes)..."
ollama run "${MODEL}" "Model loaded — ready for code completion." >/dev/null 2>&1 &

# ────────────────────────────────────────────────────────────────────────────────
#  4. Install Docker → Open WebUI
# ────────────────────────────────────────────────────────────────────────────────

info "Installing Docker (required for Open WebUI)..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # log out & back in after script finishes

info "Launching Open WebUI (ChatGPT-like interface)..."
sudo docker run -d \
  --name open-webui \
  -p ${WEBUI_PORT}:8080 \
  -v ollama:/root/.ollama \
  -v open-webui:/app/backend/data \
  --restart always \
  ghcr.io/open-webui/open-webui:ollama

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

PI_IP=$(hostname -I | awk '{print $1}')

info "──────────────────────────────────────────────────────────────"
info "Setup complete! 🎉"
info ""
info "• Ollama API     → http://${PI_IP}:${OLLAMA_PORT}"
info "• Open WebUI     → http://${PI_IP}:${WEBUI_PORT}     (open in browser)"
info "• Model loaded   → ${MODEL} (great for coding!)"
info ""
info "VS Code / Continue extension config:"
info "  apiBase: http://${PI_IP}:${OLLAMA_PORT}"
info "  model:   ${MODEL}"
info ""
info "Test commands (from another machine on LAN):"
info "  curl http://${PI_IP}:${OLLAMA_PORT}                  # should say 'Ollama is running'"
info "  curl http://${PI_IP}:${OLLAMA_PORT}/api/tags         # list models"
info ""
info "Security notes:"
info "  • Only LAN access allowed (ufw rules)"
info "  • For HTTPS / authentication → add Caddy / Nginx reverse proxy later"
info "  • Change ALLOW_FROM if your subnet is different"
info "──────────────────────────────────────────────────────────────"

info "Log out and back in (or reboot) so docker group takes effect."
info "Enjoy your private, local AI coding assistant!"

exit 0