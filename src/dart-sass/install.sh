#!/usr/bin/env bash

TARGET_VERSION="${VERSION:-"latest"}"

SASS_DIR="/usr/local/sass"

set -e

# Clean up
rm -rf /var/lib/apt/lists/*


if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
rm -f /etc/profile.d/00-restore-env.sh
echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" > /etc/profile.d/00-restore-env.sh
chmod +x /etc/profile.d/00-restore-env.sh

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

architecture="$(uname -m)"
if [ "${architecture}" != "amd64" ] && [ "${architecture}" != "x86_64" ] && [ "${architecture}" != "arm64" ] && [ "${architecture}" != "aarch64" ]; then
    echo "(!) Architecture $architecture unsupported"
    exit 1
fi

updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
        if [[ "$(cat /etc/bash.bashrc)" != *"$1"* ]]; then
            echo -e "$1" >> /etc/bash.bashrc
        fi
        if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$1"* ]]; then
            echo -e "$1" >> /etc/zsh/zshrc
        fi
    fi
}

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# ensure that the required packages are installed
check_packages curl gpg ca-certificates

# Fetch latest version of dart-sass if needed
if [ "${VERSION}" = "latest" ] || [ "${VERSION}" = "lts" ]; then
    export VERSION=$(curl -s https://api.github.com/repos/sass/dart-sass/releases/latest | grep "tag_name" | cut -d '"' -f4)
fi

# Install dart-sass if it's missing
if ! sass --version &> /dev/null ; then
    echo "Installing dart-sass..."
    mkdir -p "$SASS_DIR"

    # Install ARM or x86 version of dart-sass based on current machine
    # architecture
    if [ "$(uname -m)" == "aarch64" ]; then
        arch="arm64"
    else
        arch="x64"
    fi

    dart_sass_filename="dart-sass-${VERSION}-linux-${arch}.tar.gz"

    curl -fsSLO --compressed "https://github.com/sass/dart-sass/releases/download/${VERSION}/${dart_sass_filename}"
    tar -xzf "$dart_sass_filename" -C "$SASS_DIR"
    rm "$dart_sass_filename"
    ln -s "$SASS_DIR/dart-sass/sass" "/usr/local/bin/"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"