# VPN Administration Scripts

Ce dépôt contient une collection de scripts shell pour administrer un serveur OpenVPN et gérer la configuration du pare-feu sur un serveur Linux.

## Scripts

### 1. `adminOpenVpn.sh`

Un script d'administration OpenVPN complet avec une interface en ligne de commande (CLI) pour gérer les utilisateurs et le serveur.

**Fonctionnalités :**

*   Lister tous les utilisateurs (actifs et révoqués)
*   Voir les utilisateurs actuellement connectés
*   Ajouter un nouvel utilisateur (avec ou sans mot de passe, avec ou sans IP fixe)
*   Révoquer un utilisateur
*   Supprimer complètement un utilisateur
*   Afficher les statistiques du serveur VPN
*   Consulter les logs OpenVPN
*   Redémarrer le service OpenVPN
*   Exporter la configuration d'un utilisateur
*   Gérer les adresses IP fixes pour les utilisateurs
*   Créer et restaurer des backups de la configuration OpenVPN

**Utilisation :**

```bash
sudo ./adminOpenVpn.sh
```

### 2. `firewall_reset_and_configure.sh`

Un script pour réinitialiser et configurer le pare-feu `ufw` (Uncomplicated Firewall) avec un ensemble de règles de sécurité prédéfinies.

**Fonctionnalités :**

*   Réinitialise complètement la configuration `ufw`.
*   Définit des politiques par défaut (refuser entrant, autoriser sortant).
*   Autorise tout le trafic sur l'interface `localhost` et `tun0` (VPN).
*   Met sur liste blanche des adresses IP de confiance pour un accès total.
*   Ouvre les ports pour les services publics courants : HTTP/S, SMTP/S, IMAP/S, POP3/S, FTP.
*   Ouvre les ports pour des applications spécifiques comme Jitsi, Meilisearch, et des applications Docker.
*   Bloque l'accès public aux services d'administration (SSH, Webmin, Jupyter) et aux bases de données (MariaDB, PostgreSQL, Redis), les rendant accessibles uniquement via le VPN ou les IP de confiance.

**Utilisation :**

```bash
sudo ./firewall_reset_and_configure.sh
```

### 3. `generate_user.ssh.sh`

Un script pour la création en masse d'utilisateurs OpenVPN à partir d'un fichier.

**Fonctionnalités :**

*   Lit un fichier texte contenant une liste de noms d'utilisateurs.
*   Supporte deux formats : un utilisateur par ligne, ou `utilisateur:ip_fixe` par ligne.
*   Peut assigner un mot de passe global à tous les utilisateurs créés.
*   Génère les certificats et les fichiers de configuration `.ovpn` pour chaque utilisateur.
*   Crée des archives `.tar.gz` pour une distribution facile.

**Utilisation :**

```bash
# Créer des utilisateurs sans mot de passe
sudo ./generate_user.ssh.sh /chemin/vers/votre/fichier_utilisateurs.txt

# Créer des utilisateurs avec un mot de passe global
sudo ./generate_user.ssh.sh /chemin/vers/votre/fichier_utilisateurs.txt "VotreMotDePasseSecret"
```

## Avertissement

Ces scripts sont conçus pour être exécutés sur des systèmes Linux basés sur Debian/Ubuntu. Assurez-vous de les examiner et de les adapter à votre environnement spécifique avant de les exécuter. L'exécution de ces scripts nécessite des privilèges `root`.
