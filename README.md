<p align="center">
<img src="MITM%20attack.PNG" alt="MITM Attack" width="500"/>
</p>

<h1 align="center">MITM Attack</h1>

<p align="center">
Du scénario Hacker à la défense
</p>

---

 MITM Attack - Du Scénario Hacker à la défense 


  But : montrer, dans un environnement 100% local, comment un attaquant placé dans un lieu public (gare, aéroport, café…) pourrait intercepter le trafic d’une victime via ARP spoofing.

   Légal / éthique : ne jamais appliquer hors d’un labo dont vous avez le contrôle. Ce guide est destiné à l’apprentissage/défense et au pentest autorisé uniquement.



   Sommaire

  Contexte “hacker en lieu public”

   Architecture du labo & prérequis

  Paramétrage VirtualBox

   Adressage & tests LAN

  Découverte réseau (Nmap)

  Transformer Parrot en routeur NAT

  Configurer la victime pour sortir sur Internet via Parrot

   Attaque MITM (Bettercap ou arpspoof)

  Observation du trafic (tcpdump / Wireshark)

   Option : Proxy/Burp (HTTP)

   Nettoyage complet des machines

  Dépannage rapide
