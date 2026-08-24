
[![Bash CI](https://github.com/virg736/MITM-Attack-Scenario-Hacker-a-la-defense/actions/workflows/blash-ci.yml/badge.svg)](https://github.com/virg736/MITM-Attack-Scenario-Hacker-a-la-defense/actions/workflows/blash-ci.yml)

[![Bash CI](https://github.com/virg736/NOM-EXACT-DU-DEPOT/actions/workflows/blash-ci.yml/badge.svg)](https://github.com/virg736/NOM-EXACT-DU-DEPOT/actions/workflows/blash-ci.yml)
<p align="center">
<img src="MITM%20attack.PNG" alt="MITM Attack" width="100%"/>
</p>


<div align="center">

© 2026 Virginie Lechene

![License](https://licensebuttons.net/l/by-nd/4.0/88x31.png)

</div>


---

<div align="center">

# MITM Attack

</div>

---

## 🎯 Objectif

Reproduire, dans un **laboratoire VirtualBox contrôlé**, le principe d’une attaque **Man-in-the-Middle (MITM) par ARP spoofing** afin de comprendre comment un attaquant peut se positionner entre une victime et sa passerelle réseau.

Ce laboratoire permet notamment de :

- observer les communications entre les machines du réseau ;
- comprendre le fonctionnement de l’**ARP spoofing** ;
- analyser le trafic avec **tcpdump** et **Wireshark** ;
- observer les effets d’une attaque MITM ;
- étudier les méthodes de **détection et de protection** contre ce type d’attaque.

> [!WARNING]
> **Usage légal et éthique uniquement.**  
> Ce projet est réalisé exclusivement dans un environnement de laboratoire contrôlé. Les techniques présentées sont destinées à l’apprentissage de la cybersécurité, à la défense et aux tests d’intrusion explicitement autorisés.


---

## Table des matières

1. [Introduction](#introduction)
2. [Prérequis techniques](#prérequis-techniques)
3. [Logiciels utiles](#logiciels-utiles-côté-parrot)
4. [Paramétrage VirtualBox](#paramétrage-virtualbox)
5. [Configuration IP & tests LAN](#configuration-ip--tests-lan)
6. [Découverte réseau (Nmap)](#découverte-réseau-nmap)
7. [Transformer Parrot en routeur NAT](#transformer-parrot-en-routeur-nat)
8. [Observation du trafic (tcpdump / Wireshark)](#observation-du-trafic-tcpdump--wireshark)
9. [Attaque MITM](#attaque-mitm-bettercap-ou-arpspoof)
10. [Proxy / Burp](#option-proxyburp-http)
11. [Nettoyage complet](#nettoyage-complet-des-machines)
12. [Bonnes pratiques Wi-Fi public](#se-protéger-sur-un-wi-fi-public)
13. [Résumé & Conclusion](#résumé-express)
	
---

## 🌐 Contexte : attaque MITM par ARP spoofing

Sur un réseau local, un attaquant présent sur le même segment réseau qu’une victime peut tenter de se positionner entre celle-ci et sa passerelle.

Une technique courante consiste à effectuer un **empoisonnement ARP (ARP spoofing)** afin d’associer l’adresse IP de la passerelle à l’adresse MAC de la machine attaquante.

L’attaquant peut alors :

- intercepter une partie du trafic réseau de la victime ;
- observer certains flux non chiffrés ;
- analyser les requêtes réseau avec des outils comme **tcpdump** ou **Wireshark** ;
- étudier les traces laissées par l’empoisonnement ARP.

👉 Dans ce projet, cette situation est reproduite **uniquement dans un laboratoire VirtualBox contrôlé** afin de comprendre le fonctionnement de l’attaque, son observation, sa détection et les moyens de s’en protéger.
 
---

## Prérequis techniques

- VirtualBox 7.x ou supérieur
- 2 VM : Parrot OS (attaquant), Debian (victime)
- RAM : 2 Go minimum par VM
- CPU : 2 cœurs conseillés

---

##  Guide rapide

1. Importer les 2 VM (Parrot & Debian) dans VirtualBox.  
2. Configurer les interfaces réseau (Parrot NAT + LAB, Debian LAB).  
3. Lancer les VMs.  
4. Suivre le scénario pas à pas → depuis la section [Configuration IP & tests LAN](#configuration-ip--tests-lan).  


          🌍 Internet   (sortie NAT VirtualBox)
              │
          (NAT)
              │
        🦜 Parrot OS (Attaquant)
              │
        🔗 Réseau LAB
              │
       🖥️ Debian (Victime)


📌 **Légende :**

Dans ce TP, la machine Parrot dispose d’une interface **NAT VirtualBox** pour l’accès sortant à Internet, ainsi que d’une interface connectée au **réseau interne LAB**.

Le réseau utilisé pour les manipulations entre Parrot et Debian reste isolé dans VirtualBox et ne doit être utilisé que dans cet environnement de laboratoire contrôlé.

--- 


##  Architecture du labo & prérequis  

### VMs  

**Parrot OS (attaquant)**  
- NIC1 : NAT (sortie Internet de la VM) → enp0s8 (ex. 10.0.3.15/24)  
- NIC2 : Réseau interne (LAB) → enp0s3  

**Debian (victime)**  
- NIC1 : Réseau interne (LAB) → enp0s3  

---

###  Plan d’adressage (réseau interne LAB)  
- Parrot (enp0s3) : 192.168.100.20/24  
- Debian (enp0s3) : 192.168.100.10/24  
- Passerelle "vue par Debian" : 192.168.100.20 (Parrot)  

---

### Logiciels utiles (côté Parrot)  
- nmap  
- bettercap (ou dsniff/arpspoof)  
- tcpdump  
- wireshark  
- iptables  

- **nmap** : outil de scan réseau permettant de découvrir les machines et services actifs.  
- **bettercap** (ou **dsniff / arpspoof**) : framework d’attaque réseau, utilisé ici pour réaliser un MITM via ARP spoofing.  
- **tcpdump** : analyseur de paquets en ligne de commande, pratique pour observer rapidement le trafic.  
- **wireshark** : analyseur de paquets graphique, permettant d’inspecter en détail les flux réseau.  
- **iptables** : outil de configuration du pare-feu Linux, utilisé pour filtrer et sécuriser le trafic.  


---

##  Paramétrage VirtualBox  

**Parrot → Paramètres > Réseau**  
- Carte 1 : NAT  
- Carte 2 : Réseau interne → Nom : LAB  

**Debian → Paramètres > Réseau**  
- Carte 1 : Réseau interne → Nom : LAB  

➡️ Lancez ensuite les deux VMs.  

---

## 🔢 Configuration IP & tests LAN  

### Parrot (root)  
ip addr add 192.168.100.20/24 dev enp0s3   
ip link set enp0s3 up    
ip -br a  

### Debian (root)  
ip addr add 192.168.100.10/24 dev enp0s3   
ip link set enp0s3 up   
ip -br a

## 🔢 Configuration IP & tests LAN

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


![Forwarding sur Parrot](senarioforwarding.PNG)
---


## 🌐 Configurer la victime pour sortir sur Internet via Parrot  

### Sur Debian (root)  

Définir Parrot comme passerelle par défaut :  
ip route add default via 192.168.100.20 dev enp0s3

### Tester l'accès Internet et la résolution DNS

Tester la connectivité Internet :  

ping -c 3 8.8.8.8   

Puis tester la résolution DNS :   

ping -c 3 google.com   

✅ Si 8.8.8.8 répond, la connectivité réseau fonctionne.   
✅ Si google.com répond également, la résolution DNS fonctionne.   

---

## Observation du trafic (tcpdump / Wireshark)

 tcpdump (rapide)

tcpdump -i enp0s3      
tcpdump -i enp0s3 port 53    

### Wireshark   

Lancer Wireshark sur Parrot → interface enp0s3 (réseau LAB).

Filtres utiles (dans la barre de filtre d’affichage) :

dns → requêtes DNS

icmp → pings

 http → HTTP en clair

ip.addr == 192.168.100.10 → trafic de la victime


💡 Vous pouvez aussi ouvrir le fichier /root/capture.pcap généré par Bettercap pour l’analyser directement.

### 👀 Observation du trafic (tcpdump / Wireshark)

- 📸 tcpdump  
![tcpdump](./senarioTCP.PNG)  
[Voir en grand](./senarioTCP.PNG)

**Wireshark**
![Wireshark](senariowireshark.3.PNG)

---

## 🕵️ Analyse du trafic avec Bettercap

Sur Parrot :  
bettercap -iface enp0s3

Dans la console bettercap :     
net.recon on   
net.show   


set net.sniff.output /root/capture.pcap   
net.sniff on   


📸 Exemple d’exécution :

![Capture Bettercap](senariobettercap.PNG)

---

> [!NOTE]
> Les captures d’écran proviennent de la première version du laboratoire et montrent également des tests d’ARP spoofing.  
> Dans l’architecture finale à deux VM présentée ici, Parrot est déjà configuré comme passerelle de Debian : l’ARP spoofing n’est donc pas nécessaire pour observer le trafic transitant par Parrot.

---


### 🧪 Option : Proxy/Burp (HTTP)

> **Note :** Intercepter du trafic HTTPS exige la gestion de certificats (CA Burp).
> Pour ce TP, on garde simple → uniquement HTTP.

---

#### ⚙️ Configuration Burp (attaquant - Parrot)
- **Proxy > Proxy Listeners** : écouter sur `192.168.100.20:8080`

#### ⚙️ Configuration Firefox (victime - Debian)
- **Paramètres réseau** → Configuration manuelle du proxy
- HTTP Proxy : `192.168.100.20`
- Port : `8080`
- (Option) Cochez *Utiliser également ce proxy pour HTTPS* seulement si vous avez installé la CA.
Sinon, gardez-le uniquement pour les tests HTTP.

#### 🔎 Test
1. Dans Burp → `Proxy > Intercept` : **Intercept is on**
2. Depuis Debian → ouvrez un site HTTP comme :
👉 `http://example.com`
3. Les requêtes doivent apparaître dans Burp.

➡️ Si rien n’apparaît :
- Vérifiez IP et port.
- Assurez-vous que l’écouteur Burp est actif.
- Confirmez que Firefox n’est pas réglé sur "Pas de proxy".

---

## 🛡️ Script de protection : `protect_pro.sh`

Le projet inclut **`protect_pro.sh`**, un script pédagogique permettant d’illustrer plusieurs mécanismes de protection ARP/DNS dans un environnement de laboratoire contrôlé.

✅ Modes `block` et `detect` (`detect` conserve le durcissement ARP mais n'applique pas le blocage iptables)  
✅ Sauvegarde de la configuration (`iptables`, `arptables`, `sysctl`, table ARP)  
✅ Entrée ARP statique pour la passerelle  
✅ Verrouillage du DNS classique vers un résolveur défini (ex. `1.1.1.1`)  
✅ Journalisation des actions via syslog  

📸 **Preuve en image :**  
`1.1.1.1` autorisé ✅ | `8.8.8.8` bloqué 🚫

**Objectif :** illustrer, dans un laboratoire pédagogique, plusieurs mécanismes de protection contre les risques liés à l’ARP spoofing et à la configuration DNS.

### ⚠️ Note importante

Ce script est avant tout **pédagogique** :

- idéal pour apprendre, tester et sensibiliser ;
- utile en laboratoire de formation, pentest interne autorisé ou POC ;
- non destiné tel quel à un environnement de production.

---

## 🧹 Nettoyage

Après les tests, restaurez la configuration réseau des machines et supprimez les réglages temporaires appliqués pendant le laboratoire.

![Nettoyage Debian](senarionettoyagedebian.PNG)

---

### Parrot (attaquant)

Arrêtez les outils d’analyse encore actifs, désactivez les réglages temporaires appliqués pendant le laboratoire et restaurez la configuration réseau initiale de la machine.

![Nettoyage Parrot](senarionettoyageparrot.PNG)

---

## 🌐 Se protéger sur un Wi-Fi public

### 🔒 Bonnes pratiques utilisateur

- ☑️ **Utiliser un VPN** → chiffre le trafic entre l’appareil et le serveur VPN, ce qui limite les risques d’interception sur un Wi-Fi public.
- ☑️ **Éviter les réseaux Wi-Fi ouverts ou dépourvus de chiffrement WPA2/WPA3.**
- ☑️ **Désactiver la connexion automatique** aux anciens hotspots enregistrés.
- ☑️ **Ne jamais installer de certificats inconnus** (ex. si une page vous demande d’accepter un certificat suspect → ne pas continuer).
- ☑️ **Privilégier la 4G/5G pour les opérations sensibles** (banque, achats, données confidentielles).
- ☑️ **Vérifier les alertes de certificat dans le navigateur** et interrompre la connexion en cas d’avertissement inattendu.
- ☑️ **Désactiver le partage de fichiers** sur les réseaux publics (Windows / macOS → désactiver le partage réseau).

---

## Côté administrateur (Wi-Fi public)

- Configurer le Wi-Fi avec **WPA2-Enterprise / WPA3** et éviter les réseaux ouverts sans chiffrement.
- Mettre en place une **segmentation VLAN** et activer l’**isolation client-à-client**.
- Activer **Dynamic ARP Inspection (DAI)** et **Port Security** si l’équipement réseau le permet.
- Surveiller le réseau avec un **IDS/IPS** afin de détecter notamment les anomalies ARP et certains comportements DNS suspects.

## Résumé express

- 🔗 **VPN recommandé** sur les réseaux publics
- 🚫 Éviter les réseaux Wi-Fi ouverts
- 🔐 **WPA2/WPA3** + isolation des clients
- 📶 Privilégier la **4G/5G** pour les opérations sensibles

---

## 🔒 Conclusion

Ce projet présente, dans un **laboratoire VirtualBox contrôlé**, les principes d’une attaque **Man-in-the-Middle (MITM)** et l’observation du trafic réseau.

Il permet notamment de comprendre :
- le rôle de l’**ARP** dans un réseau local ;
- l’analyse du trafic avec **tcpdump, Wireshark et Bettercap** ;
- les risques liés aux réseaux Wi-Fi publics ;
- plusieurs mécanismes de **détection et de protection**.

> ⚠️ Les manipulations présentées sont réalisées uniquement à des fins pédagogiques, défensives et dans un environnement autorisé.

L’objectif principal est de mieux comprendre ces attaques afin de savoir **les identifier, les analyser et s’en protéger**.


---

✍️ Auteur : *Virginie Lechene*

---

## Licence
Le script est publié sous la licence MIT.

## À propos de l’usage
Ce projet est destiné exclusivement à des fins pédagogiques, notamment dans le cadre de :
- d’une formation en cybersécurité,
- tests d’intrusion explicitement autorisés,
- d’analyses réseau dans un environnement contrôlé.

⚠️ L’auteure ne cautionne ni n’autorise l’utilisation de ce script en dehors d’un cadre légal strictement défini.
Toute utilisation non conforme est interdite et relève uniquement de la responsabilité de l’utilisateur.

## 📷 Droits sur les visuels

Les visuels de ce dépôt sont protégés par la licence CC BY-ND 4.0.
Attribution obligatoire – Modification interdite.

© 2026 Virginie Lechene





