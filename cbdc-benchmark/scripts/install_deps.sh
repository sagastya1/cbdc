#!/usr/bin/env bash
# Install all dependencies on Amazon Linux 2023 / Ubuntu EC2
set -euo pipefail

log() { echo "[INSTALL] $*"; }

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    fi
}

OS=$(detect_os)
log "Detected OS: $OS"

install_amazon_linux() {
    log "Installing for Amazon Linux 2023..."
    sudo dnf update -y
    
    # Docker
    sudo dnf install -y docker
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    
    # Docker Compose v2
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    sudo ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
    # Node.js 18
    curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
    sudo dnf install -y nodejs
    
    # Python & tools
    sudo dnf install -y python3 python3-pip jq git curl wget
    
    # Solidity compiler
    sudo pip3 install py-solc-x
    python3 -c "from solcx import install_solc; install_solc('0.8.19')"
}

install_ubuntu() {
    log "Installing for Ubuntu..."
    sudo apt-get update -y
    
    # Docker
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker && sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    sudo ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
    # Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Tools
    sudo apt-get install -y python3 python3-pip jq git curl wget
    sudo pip3 install py-solc-x
    python3 -c "from solcx import install_solc; install_solc('0.8.19')"
}

case "$OS" in
    amzn)   install_amazon_linux ;;
    ubuntu) install_ubuntu ;;
    *)      log "Unsupported OS: $OS. Attempting Ubuntu path..."; install_ubuntu ;;
esac

# Python packages
log "Installing Python packages..."
pip3 install --user matplotlib pandas numpy jinja2 requests web3

# Node packages (Caliper + Web3)
log "Installing Node packages..."
npm install --global @hyperledger/caliper-cli@0.6.0
caliper bind --caliper-bind-sut ethereum:latest

log ""
log "════════════ Installation Complete ════════════"
log "IMPORTANT: Log out and back in for Docker group changes to take effect."
log "Then run: ./run.sh"
