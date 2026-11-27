#!/bin/bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: use sudo bash"; exit 1; }

FILE=/etc/netplan/60-dns.yaml

IFACE="${IFACE:-$(ip route show default | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
[ -n "$IFACE" ] || { echo "Could not find the main network interface."; exit 1; }

GATEWAY="$(ip route show default dev "$IFACE" | awk '{for(i=1;i<NF;i++) if($i=="via"){print $(i+1); exit}}')"
DNS_SERVERS="${DNS_SERVERS:-${GATEWAY:+$GATEWAY }8.8.8.8}"

LIST=""
IFS=' ' read -r -a ARR <<< "${DNS_SERVERS//,/ }"
for s in "${ARR[@]}"; do
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Not a valid IPv4 address: $s"; exit 1; }
  LIST="${LIST:+$LIST, }$s"
done
[ -n "$LIST" ] || { echo "No DNS servers given."; exit 1; }

ip -4 addr show dev "$IFACE" | grep dynamic > /dev/null || { echo "$IFACE has a fixed (static) address, so this script will not touch it."; exit 1; }

BACKUP=""
if [ -f "$FILE" ]; then BACKUP="$(mktemp)"; cp -p "$FILE" "$BACKUP"; fi
restore() { if [ -n "$BACKUP" ]; then cp -p "$BACKUP" "$FILE"; else rm -f "$FILE"; fi; }

echo "Interface: $IFACE   DNS servers: $LIST"

cat > "$FILE" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      dhcp6-overrides:
        use-dns: false
      nameservers:
        addresses: [${LIST}]
EOF
chmod 600 "$FILE"

if ! netplan generate; then
  echo "Netplan rejected the settings. Putting things back."
  restore
  exit 1
fi

netplan apply
sleep 5

OK=0
for _ in 1 2 3 4 5 6; do
  resolvectl query registry-1.docker.io > /dev/null 2>&1 && OK=$((OK + 1))
done
if [ "$OK" -lt 5 ]; then
  echo "DNS test failed (${OK} of 6 lookups worked). Putting things back."
  restore
  netplan apply
  exit 1
fi

echo
resolvectl dns "$IFACE"
ip -br a show "$IFACE"
echo "Done: DNS fixed (${OK} of 6 test lookups worked)."
