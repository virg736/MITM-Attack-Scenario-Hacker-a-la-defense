#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo ./protect_mitm_pro.sh --iface eth0 --gw-ip 192.168.1.1 --dns 1.1.1.1 --mode block
# Modes: block | detect  (detect = pas de blocage, seulement des logs)

# --- paramètres ---
IFACE=""
GATEWAY_IP=""
GATEWAY_MAC=""
LOCK_DNS_TO="1.1.1.1"
MODE="block"

log(){ echo "[mitm-guard] $*"; logger -t mitm-guard -- "$*"; }

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface) IFACE="$2"; shift 2;;
    --gw-ip) GATEWAY_IP="$2"; shift 2;;
    --gw-mac) GATEWAY_MAC="$2"; shift 2;;
    --dns) LOCK_DNS_TO="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    *) echo "Arg inconnu: $1"; exit 1;;
  esac
done

[[ -n "$IFACE" && -n "$GATEWAY_IP" ]] || { echo "Requis: --iface et --gw-ip"; exit 1; }

# --- prérequis ---
command -v ip >/dev/null || { echo "Installe iproute2"; exit 1; }
if command -v iptables >/dev/null; then FW=iptables
elif command -v nft >/dev/null; then FW=nft # (placeholder simple)
else echo "Installe iptables ou nftables"; exit 1
fi
command -v arptables >/dev/null || { echo "Installe arptables"; exit 1; }

# --- chemins sauvegarde ---
STATE_DIR=/etc/mitm-guard
mkdir -p "$STATE_DIR"
SYSCTL_BACKUP="$STATE_DIR/sysctl.backup"
IPTABLES_BACKUP="$STATE_DIR/iptables.rules"
ARPTABLES_BACKUP="$STATE_DIR/arptables.rules"
NEIGH_BACKUP="$STATE_DIR/neigh.backup"

# --- détecter MAC GW si non fournie ---
if [[ -z "${GATEWAY_MAC:-}" ]]; then
  log "Résolution MAC pour $GATEWAY_IP…"
  ping -c1 -W1 "$GATEWAY_IP" >/dev/null 2>&1 || true
  GATEWAY_MAC="$(ip neigh show dev "$IFACE" | awk -v ip="$GATEWAY_IP" '$1==ip && $4~/..:..:..:..:..:../{print $5; exit}')"
  [[ -n "$GATEWAY_MAC" ]] || { echo "Impossible de déterminer la MAC passerelle. Fournis --gw-mac"; exit 1; }
fi

log "Interface=$IFACE  GW=$GATEWAY_IP ($GATEWAY_MAC)  DNS=$LOCK_DNS_TO  MODE=$MODE"

# --- snapshots ---
sysctl -a 2>/dev/null | grep -E 'net\.ipv4\.conf\..*\.arp_(ignore|announce)' > "$SYSCTL_BACKUP" || true
ip neigh show dev "$IFACE" > "$NEIGH_BACKUP" || true
$FW-save > "$IPTABLES_BACKUP" || true
arptables-save > "$ARPTABLES_BACKUP" || true

# --- durcissement noyau ---
for p in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_ignore; do [[ -e $p ]] && echo 2 > "$p"; done
for p in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_announce; do [[ -e $p ]] && echo 2 > "$p"; done

# --- entrée ARP statique vers la GW ---
ip neigh replace "$GATEWAY_IP" lladdr "$GATEWAY_MAC" nud permanent dev "$IFACE"

# --- règles ARP (arptables) ---
arptables -F
arptables -P INPUT DROP
arptables -P OUTPUT ACCEPT
# autoriser ARP de/vers la passerelle
arptables -A INPUT  -i "$IFACE" --source-mac "$GATEWAY_MAC" -j ACCEPT
arptables -A OUTPUT -o "$IFACE" --dest-mac   "$GATEWAY_MAC" -j ACCEPT

if [[ "$MODE" == "detect" ]]; then
  log "MODE detect: pas de blocage iptables; on trace seulement les anomalies ARP."
else
  # --- iptables: politique adaptée à un poste ---
  # 1) autoriser connexions établies/relatées
  $FW -C OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || $FW -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  # 2) DHCP (utile en poste client)
  $FW -C OUTPUT -p udp --dport 67:68 -j ACCEPT 2>/dev/null || $FW -A OUTPUT -p udp --dport 67:68 -j ACCEPT
  # 3) NTP
  $FW -C OUTPUT -p udp --dport 123 -j ACCEPT 2>/dev/null || $FW -A OUTPUT -p udp --dport 123 -j ACCEPT
  # 4) DNS: n’autoriser que LOCK_DNS_TO (UDP et TCP 53)
  for proto in udp tcp; do
    $FW -C OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT 2>/dev/null || \
    $FW -A OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT
    $FW -C OUTPUT -p "$proto" --dport 53 -j REJECT 2>/dev/null || \
    $FW -A OUTPUT -p "$proto" --dport 53 -j REJECT
  done
  # 5) par défaut, on laisse le reste sortir (pour la démo/usage quotidien),
  #    mais on LOG les paquets port 53 refusés pour visibilité
  $FW -C OUTPUT -p udp --dport 53 -j LOG 2>/dev/null || $FW -A OUTPUT -p udp --dport 53 -j LOG --log-prefix "DNS_BLOCK "
  $FW -C OUTPUT -p tcp --dport 53 -j LOG 2>/dev/null || $FW -A OUTPUT -p tcp --dport 53 -j LOG --log-prefix "DNS_BLOCK "
fi

log "Protection appliquée. Pour restaurer: sudo ./restore_mitm.sh"
