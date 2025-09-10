#!/usr/bin/env bash
set -euo pipefail

# ===========================
#  Protect MITM (ARP/DNS) v1
#  Tested on Debian/Ubuntu/Parrot
# ===========================

# >>>> À PERSONNALISER <<<<
IFACE="${IFACE:-enp0s3}"              # Interface LAN
GATEWAY_IP="${GATEWAY_IP:-192.168.100.20}"  # IP de la passerelle légitime (routeur)
GATEWAY_MAC="${GATEWAY_MAC:-}"        # MAC de la passerelle (optionnel: si vide, auto-détecté)
LOCK_DNS_TO="${LOCK_DNS_TO:-1.1.1.1}" # Résolveur DNS autorisé

# --- vérifs rapides ---
if ! command -v ip >/dev/null; then
  echo "Manque 'ip' (iproute2)." >&2; exit 1
fi
if ! command -v arptables >/dev/null; then
  echo "Installe 'arptables' (sudo apt install arptables)." >&2; exit 1
fi
if ! command -v iptables >/dev/null; then
  echo "Installe 'iptables'." >&2; exit 1
fi

# --- détecte la MAC de la GW si non fournie ---
if [[ -z "$GATEWAY_MAC" ]]; then
  echo "[*] Résolution MAC pour $GATEWAY_IP sur $IFACE…"
  # envoie une requête ARP pour peupler la neigh table
  ping -c1 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
  GATEWAY_MAC="$(ip neigh show dev "$IFACE" | awk -v ip="$GATEWAY_IP" '$1==ip && $4 ~ /..:..:..:..:..:../ {print $5; exit}')"
  if [[ -z "$GATEWAY_MAC" ]]; then
    echo "Impossible de déterminer la MAC de la passerelle. Fournis GATEWAY_MAC=aa:bb:cc:dd:ee:ff" >&2
    exit 1
  fi
fi

echo "[*] Interface: $IFACE"
echo "[*] Passerelle: $GATEWAY_IP ($GATEWAY_MAC)"
echo "[*] DNS autorisé: $LOCK_DNS_TO"

# --- sauvegardes ---
mkdir -p /etc/mitm-guard
SYSCTL_SNAPSHOT=/etc/mitm-guard/sysctl.backup
IPTABLES_SAVE=/etc/mitm-guard/iptables.rules
ARPTABLES_SAVE=/etc/mitm-guard/arptables.rules
NEIGH_SAVE=/etc/mitm-guard/neigh.backup

echo "[*] Snapshot sysctl…"
sysctl -a 2>/dev/null | grep -E 'net\.ipv4\.conf\..*arp_(ignore|announce)' > "$SYSCTL_SNAPSHOT" || true

echo "[*] Snapshot ip neigh…"
ip neigh show dev "$IFACE" > "$NEIGH_SAVE" || true

echo "[*] Snapshot iptables/arptables…"
iptables-save > "$IPTABLES_SAVE" || true
arptables-save > "$ARPTABLES_SAVE" || true

# --- durcissement noyau (ARP) ---
# arp_ignore=2 : répondre ARP seulement si l’IP est sur l’interface cible
# arp_announce=2 : toujours annoncer la meilleure adresse source (réduit l’usurpation)
for path in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_ignore; do
  [[ -e "$path" ]] && echo 2 > "$path"
done
for path in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_announce; do
  [[ -e "$path" ]] && echo 2 > "$path"
done

# --- verrouillage ARP ---
echo "[*] Entrée ARP statique pour la passerelle…"
ip neigh replace "$GATEWAY_IP" lladdr "$GATEWAY_MAC" nud permanent dev "$IFACE"

echo "[*] Politique ARP: DROP par défaut, et n’autoriser que la GW…"
arptables -F
arptables -P INPUT DROP
arptables -P OUTPUT ACCEPT
# Autoriser ARP request et reply venant/vers la MAC de la passerelle
arptables -A INPUT  -i "$IFACE" --source-mac "$GATEWAY_MAC" -j ACCEPT
arptables -A INPUT  -i "$IFACE" --arp-op Request -j ACCEPT   # on laisse les requêtes ARP (lisibilité LAN)
# Optionnel: protéger aussi les sorties ARP vers la GW
arptables -A OUTPUT -o "$IFACE" --dest-mac "$GATEWAY_MAC" -j ACCEPT

# --- verrouillage DNS ---
echo "[*] Verrouillage DNS: n’autoriser que $LOCK_DNS_TO:53 (UDP/TCP)…"
# Politique générale : autoriser ESTABLISHED, puis DNS autorisé, bloquer le reste de 53
iptables -C OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

for proto in udp tcp; do
  iptables -C OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT 2>/dev/null || \
    iptables -A OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT
  iptables -C OUTPUT -p "$proto" --dport 53 -j REJECT 2>/dev/null || \
    iptables -A OUTPUT -p "$proto" --dport 53 -j REJECT
done

# (Option) verrouiller /etc/resolv.conf à ce DNS
if [[ -w /etc/resolv.conf ]]; then
  echo "[*] Écrit /etc/resolv.conf → nameserver $LOCK_DNS_TO"
  printf 'nameserver %s\n' "$LOCK_DNS_TO" > /etc/resolv.conf
fi

echo
echo "[OK] Protection ARP/DNS appliquée."
echo "     Sauvegardes: $SYSCTL_SNAPSHOT | $IPTABLES_SAVE | $ARPTABLES_SAVE | $NEIGH_SAVE"
echo "     Pour restaurer : ./restore_mitm.sh"
