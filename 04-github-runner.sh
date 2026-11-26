#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "This script is for x86_64 servers only"; exit 1; }

RUNNER_VERSION="2.338.2"
RUNNER_SHA256="baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
RUNNER_URL="https://github.com/adrxp3"
RUNNER_USER="github-runner"
RUNNER_DIR="/opt/actions-runner"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
TARBALL="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

RUNNER_TOKEN="${RUNNER_TOKEN:-}"
if [ -z "$RUNNER_TOKEN" ]; then
  read -r -s -p "Paste the runner token and press Enter: " RUNNER_TOKEN < /dev/tty
  echo
fi
[ -n "$RUNNER_TOKEN" ] || { echo "No token given"; exit 1; }

apt-get update -y
apt-get install -y curl tar

id "$RUNNER_USER" > /dev/null 2>&1 || useradd --system --create-home --shell /bin/bash "$RUNNER_USER"

if [ ! -f "$RUNNER_DIR/config.sh" ]; then
  mkdir -p "$RUNNER_DIR"
  curl -fsSL -o "/tmp/$TARBALL" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
  echo "${RUNNER_SHA256}  /tmp/${TARBALL}" | sha256sum -c -
  tar xzf "/tmp/$TARBALL" -C "$RUNNER_DIR"
  rm -f "/tmp/$TARBALL"
fi
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

"$RUNNER_DIR/bin/installdependencies.sh"

if [ ! -f "$RUNNER_DIR/.runner" ]; then
  runuser -u "$RUNNER_USER" -- bash -c 'cd "$1" && ./config.sh --unattended --replace --url "$2" --token "$3" --name "$4"' _ "$RUNNER_DIR" "$RUNNER_URL" "$RUNNER_TOKEN" "$RUNNER_NAME"
fi

cd "$RUNNER_DIR"
compgen -G "/etc/systemd/system/actions.runner.*" > /dev/null || ./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status | head -n 5

echo
echo "Done: GitHub runner '${RUNNER_NAME}' is running as a service for ${RUNNER_URL}."
echo "Use in workflows:  runs-on: self-hosted"
