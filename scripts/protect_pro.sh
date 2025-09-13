#!/usr/bin/env bash
# -------------------------------------------------------------------
# protect_pro.sh — Protection locale contre MITM (ARP/DNS)
# Usage :
#   sudo ./protect_pro.sh --iface enp0s3 --gw-ip 10.0.2.2 --dns 1.1.1.1 --mode block [--gw-mac AA:BB:CC:DD:EE:FF]
# Modes :
#   block  = applique les règles (par défaut)
#   detect = n’applique que l’ARP hardening (pas de blocage iptables), utile en démo/observation
# -------------------------------------------------------------------

set -euo pipefail
PATH=$PATH:/usr/sbin

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
    --iface)   IFACE="$2"; shift 2;;
    --gw-ip)   GATEWAY_IP="$2"; shift 2;;
    --gw-mac)  GATEWAY_MAC="$2"; shift 2;;
    --dns)     LOCK_DNS_TO="$2"; shift 2;;
    --mode)    MODE="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: sudo $0 --iface IFACE --gw-ip GW_IP [--gw-mac MAC] [--dns IP] [--mode block|detect]
Exemples:
  sudo $0 --iface enp0s3 --gw-ip 10.0.2.2 --dns 1.1.1.1 --mode block
  sudo $0 --iface wlan0  --gw-ip 192.168.1.1 --mode detect
EOF
      exit 0;;
    *) echo "Arg inconnu: $1"; exit 1;;
  esac
done

# --- auto-détection basique si manquant ---
IFACE="${IFACE:-$(ip route | awk '/^default/ {print $5; exit}')}"; : "${IFACE:?Requis: --iface}"
GATEWAY_IP="${GATEWAY_IP:-$(ip route | awk '/^default/ {print $3; exit}')}"; : "${GATEWAY_IP:?Requis: --gw-ip}"

# --- prérequis ---
command -v ip >/dev/null || { echo "Installe iproute2"; exit 1; }
if command -v iptables >/dev/null; then
  FW=iptables
  FWSAVE=iptables-save
  FWRESTORE=iptables-restore
elif command -v nft >/dev/null; then
  # Placeholder simple: on continue avec iptables si dispo, sinon on informera l'utilisateur
  echo "[WARN] nftables détecté. Ce script applique des règles iptables legacy."
  command -v iptables >/dev/null || { echo "Installe iptables (mode legacy)"; exit 1; }
  FW=iptables
  FWSAVE=iptables-save
  FWRESTORE=iptables-restore
else
  echo "Installe iptables ou nftables"; exit 1
fi
command -v arptables >/dev/null || { echo "Installe arptables"; exit 1; }

# --- validation interface ---
ip link show "$IFACE" >/dev/null 2>&1 || { echo "Interface introuvable: $IFACE"; exit 1; }

# --- chemins sauvegarde ---
STATE_DIR=/etc/mitm-guard
mkdir -p "$STATE_DIR"
SYSCTL_BACKUP="$STATE_DIR/sysctl.backup"
IPTABLES_BACKUP="$STATE_DIR/iptables.rules"
ARPTABLES_BACKUP="$STATE_DIR/arptables.rules"
NEIGH_BACKUP="$STATE_DIR/neigh.backup"

# --- détecter MAC GW si non fournie ---
if [[ -z "${GATEWAY_MAC:-}" ]]; then
  log "Résolution MAC pour $GATEWAY_IP sur $IFACE…"
  # peupler la table ARP
  ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
  # lecture robuste de la MAC (cherche 'lladdr')
  GATEWAY_MAC="$(
    ip neigh show dev "$IFACE" |
    awk -v ip="$GATEWAY_IP" '
      $1==ip {
        for(i=1;i<=NF;i++) if($i=="lladdr"){ print $(i+1); exit }
      }'
  )"
  if [[ -z "$GATEWAY_MAC" ]]; then
    echo "Impossible de déterminer la MAC passerelle. Fournis --gw-mac AA:BB:CC:DD:EE:FF"
    exit 1
  fi
fi

log "Interface=$IFACE  GW=$GATEWAY_IP ($GATEWAY_MAC)  DNS=$LOCK_DNS_TO  MODE=$MODE"

# --- snapshots ---
sysctl -a 2>/dev/null | grep -E 'net\.ipv4\.conf\..*\.arp_(ignore|announce)' > "$SYSCTL_BACKUP" || true
ip neigh show dev "$IFACE" > "$NEIGH_BACKUP" || true
$FWSAVE > "$IPTABLES_BACKUP" || true
arptables-save > "$ARPTABLES_BACKUP" || true

# --- durcissement noyau ARP ---
for p in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_ignore;   do [[ -e "$p" ]] && echo 2 > "$p"; done
for p in /proc/sys/net/ipv4/conf/{all,"$IFACE"}/arp_announce; do [[ -e "$p" ]] && echo 2 > "$p"; done

# --- entrée ARP statique vers la GW ---
ip neigh replace "$GATEWAY_IP" lladdr "$GATEWAY_MAC" nud permanent dev "$IFACE"

# --- règles ARP (arptables) ---
arptables -F
arptables -P INPUT DROP
arptables -P OUTPUT ACCEPT
# autoriser ARP provenant de la vraie passerelle (en entrée)
arptables -A INPUT  -i "$IFACE" --source-mac      "$GATEWAY_MAC" -j ACCEPT
# (optionnel) autoriser ARP vers la passerelle (en sortie)
arptables -A OUTPUT -o "$IFACE" --destination-mac "$GATEWAY_MAC" -j ACCEPT

if [[ "$MODE" == "detect" ]]; then
  log "MODE detect: pas de blocage iptables; on trace seulement les anomalies ARP."
else
  # --- iptables: politique adaptée à un poste ---
  # 1) autoriser connexions établies/relatées
  $FW -C OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  $FW -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

  # 2) DHCP client (utile sur poste)
  $FW -C OUTPUT -p udp --dport 67:68 -j ACCEPT 2>/dev/null || \
  $FW -A OUTPUT -p udp --dport 67:68 -j ACCEPT

  # 3) NTP
  $FW -C OUTPUT -p udp --dport 123 -j ACCEPT 2>/dev/null || \
  $FW -A OUTPUT -p udp --dport 123 -j ACCEPT

  # 4) DNS: n’autoriser que LOCK_DNS_TO (UDP et TCP 53), refuser le reste
  for proto in udp tcp; do
    $FW -C OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT 2>/dev/null || \
    $FW -A OUTPUT -p "$proto" -d "$LOCK_DNS_TO" --dport 53 -j ACCEPT
    $FW -C OUTPUT -p "$proto" --dport 53 -j REJECT 2>/dev/null || \
    $FW -A OUTPUT -p "$proto" --dport 53 -j REJECT
  done

  # 5) journaliser les requêtes DNS refusées (visibilité)
  $FW -C OUTPUT -p udp --dport 53 -j LOG 2>/dev/null || \
  $FW -A OUTPUT -p udp --dport 53 -j LOG --log-prefix "DNS_BLOCK "
  $FW -C OUTPUT -p tcp --dport 53 -j LOG 2>/dev/null || \
  $FW -A OUTPUT -p tcp --dport 53 -j LOG --log-prefix "DNS_BLOCK "
fi

log "Protection appliquée. Pour restaurer : sudo ./restore_mitm.sh"