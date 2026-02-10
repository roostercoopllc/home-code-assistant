# Local AI Code Assistant Setup on Raspberry Pi 5

**Goal**  
Run Ollama + Qwen2.5-Coder 7B + Open WebUI on a Raspberry Pi (ideally Pi 5 8GB)  
→ Provide fast, private, local code completion in VS Code (via Continue extension)  
→ Provide a beautiful ChatGPT-like web interface on your local network

**Last tested / written for**  
- [Raspberry Pi OS (64-bit Bookworm or later)](https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64.img.xz)  
- [Pi 5 with 8 GB RAM recommended](https://vilros.com/products/raspberry-pi-5?variant=40065551302750)
- Ollama v0.3.x / Open WebUI latest (as of 2025)

## Quick Start – How to Run

1. **Save the script**  
On your Raspberry Pi, clone the repository:

```bash
git clone https://github.com/roostercoopllc/home-code-assistant.git
cd home-code-assistant
```

2. **Make it executable**
```bash
chmod +x ./scripts/install-all.sh
```

3. **(Optional) Customize before running
```bash
MODEL="qwen2.5-coder:7b"           # ← change to :3b if too slow
ALLOW_FROM="192.168.0.0/16"        # ← tighten to your subnet e.g. 192.168.1.0/24
```

4. **Run the installation**
```bash
./install-all.sh
```

NOTE: → It will take 10–30 minutes depending on internet speed and model download.

5. **After the script finishes**
* Log out and log back in (or reboot) so the Docker group membership takes effect:

```bash
exit
# or
sudo reboot
```

* Fine your Pi's IP Address
```bash
hostname -I
```

6. **Access the services**

Example output: 192.168.1.105

|Service|URL on your local network|Purpose|
|-------|-------------------------|-------|
|Open WebUI (browser)|http://192.168.1.105:8080|ChatGPT-like interface|
|Ollama API|http://192.168.1.105:11434|For VS Code / Continue extension|
|Continue config|See section below|AI code completion in VS Code|

## VS Code + Continue Extension Setup

1. Install the Continue extension in VS Code → Search “Continue” in Extensions panel or visit: https://continue.dev
2. Open Continue settings 
    * Press Ctrl+Shift+P → type “Continue: Open config.json”
3. Replace or add the following block in ~/.continue/config.json:

```bash
{
  "models": [
    {
      "title": "Qwen2.5-Coder 7B (Raspberry Pi)",
      "provider": "ollama",
      "model": "qwen2.5-coder:7b",
      "apiBase": "http://192.168.1.105:11434"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Qwen2.5-Coder 7B (Raspberry Pi)",
    "provider": "ollama",
    "model": "qwen2.5-coder:7b",
    "apiBase": "http://192.168.1.105:11434"
  },
  "tabAutocompleteOptions": {
    "maxPromptTokens": 350,
    "debounceDelay": 300
  }
}
```

NOTE: → Replace 192.168.1.105 with your actual Pi IP.

4. Start typing code → press Tab to accept suggestions.

## Troubleshooting & Tips
* Model too slow?
Edit script → change to qwen2.5-coder:3b or qwen2.5:3b → re-run ./install-all.sh

* Firewall blocking access?
Check ufw rules:
```bash
sudo ufw status
```
Temporarily disable (not recommended long-term):
```bash
sudo ufw disable
```

* Docker not working after reboot?
Make sure you're in the docker group:
```bash
Make sure you're in the docker group:
```
If not → sudo usermod -aG docker $USER then log out/in.

* Want HTTPS later?
Install Caddy or Nginx → reverse proxy ports 8080 and/or 11434 with Let’s Encrypt.

## What's installed

|Component|Purpose|Port|Accessible from|
|---------|-------|----|---------------|
|Ollama|LLM runtime & API server|11434|Local network|
|qwen2.5-coder:7b|Excellent 7B coding model (quantized)|—|via Ollama|
|Docker|Container runtime|—|—|
|Open WebUI|Modern web chat UI for Ollama models|8080|Local network|
|ufw|Basic firewall (LAN-only access enforced)|—|—|

Questions / improvements → feel free to ask.