#!/bin/bash

set -e

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Last2334/onekey-p-linux/main/install.sh"
TMP_SCRIPT="$(mktemp /tmp/onekey-p-linux-install.XXXXXX.sh)"
PROX_CMD="/usr/local/bin/prox"

cleanup() {
    rm -f "$TMP_SCRIPT"
}

trap cleanup EXIT

echo "[bootstrap] downloading install.sh ..."
curl -fsSL "$INSTALL_SCRIPT_URL" -o "$TMP_SCRIPT"
chmod +x "$TMP_SCRIPT"

echo "[bootstrap] installing prox ..."
bash "$TMP_SCRIPT" bootstrap-prox

if [ -x "$PROX_CMD" ]; then
    echo "[bootstrap] launching prox ..."
    exec "$PROX_CMD"
fi

echo "[bootstrap] prox installation failed"
exit 1
