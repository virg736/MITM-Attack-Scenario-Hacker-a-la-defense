#!/usr/bin/env bash
set -euo pipefail

# protect_pro.sh - Protection ARP/DNS pour le laboratoire
# SPDX-License-Identifier: MIT

IFACE="${IFACE:-enp0s3}"
GATEWAY_IP="${GATEWAY_IP:-192.168.100.20}"
DNS="${DNS:-1.1.1.1}"

[[ $EUID -eq 0 ]] || {
  echo "Lancez ce script avec sudo."
  exit 1
}

command -v ip >/dev/null || {
  echo "Commande 'ip' manquante."
  exit 1
}

command -v iptables >/dev/null || {
  echo "Commande 'iptables' manquante."
  exit 1
}

ip link show "$IFACE" >/dev/null 2>&1 || {
  echo "Interface introuvable : $IFACE"
  exit 1
}

echo "[*] Recherche de la MAC de la passerelle..."

ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true

GATEWAY_MAC="$(
  ip neigh show "$GATEWAY_IP" dev "$IFACE" |
    awk '/lladdr/ {print $5; exit}'
)"

[[ -n $GATEWAY_MAC ]] || {
  echo "Impossible de déterminer la MAC de $GATEWAY_IP."
  exit 1
}

echo "[*] Passerelle : $GATEWAY_IP ($GATEWAY_MAC)"

# Protection contre l'usurpation ARP de la passerelle
ip neigh replace "$GATEWAY_IP" \
  lladdr "$GATEWAY_MAC" \
  nud permanent \
  dev "$IFACE"

# Autoriser uniquement le DNS choisi sur le port 53
for proto in udp tcp; do
  iptables -C OUTPUT -p "$proto" -d "$DNS" --dport 53 -j ACCEPT 2>/dev/null ||
    iptables -A OUTPUT -p "$proto" -d "$DNS" --dport 53 -j ACCEPT

  iptables -C OUTPUT -p "$proto" --dport 53 -j REJECT 2>/dev/null ||
    iptables -A OUTPUT -p "$proto" --dport 53 -j REJECT
done

echo
echo "✅ Protection appliquée"
echo "Interface  : $IFACE"
echo "Passerelle : $GATEWAY_IP"
echo "DNS        : $DNS"
