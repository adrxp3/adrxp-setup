#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }

export PATH="$PATH:/var/lib/rancher/rke2/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

if [ -z "${TUNNEL_TOKEN:-}" ]; then
  read -r -s -p "Paste your tunnel token and press Enter: " TUNNEL_TOKEN < /dev/tty
  echo
fi
[ -n "$TUNNEL_TOKEN" ] || { echo "No token given"; exit 1; }

kubectl get nodes > /dev/null

kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -

printf %s "$TUNNEL_TOKEN" | kubectl -n cloudflare create secret generic tunnel-token \
  --from-file=token=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloudflared
  namespace: cloudflare
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloudflared
  template:
    metadata:
      labels:
        app: cloudflared
    spec:
      containers:
        - name: cloudflared
          image: cloudflare/cloudflared:latest
          command: ["cloudflared", "tunnel", "--no-autoupdate", "run"]
          env:
            - name: TUNNEL_TOKEN
              valueFrom:
                secretKeyRef:
                  name: tunnel-token
                  key: token
EOF

kubectl -n cloudflare rollout status deployment/cloudflared --timeout=180s
echo "Done: cloudflared is running."
