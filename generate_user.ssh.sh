#!/bin/bash

# Script de création en masse d'utilisateurs OpenVPN
# Avec tls-crypt, IPs fixes, et mot de passe unique

# Pas de set -e pour éviter les problèmes avec les compteurs
# set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
EASYRSA_DIR="/etc/openvpn/easy-rsa"
OPENVPN_DIR="/etc/openvpn"
CLIENT_DIR="/var/www/html/vpn-clients"
CCD_DIR="/etc/openvpn/ccd"
SERVER_IP=$(curl -s ifconfig.me)

# ═══════════════════════════════════════════════════════════
# CONFIGURATION DU MOT DE PASSE GLOBAL (Optionnel)
# ═══════════════════════════════════════════════════════════
# Option 1: Définir ici directement (décommentez et modifiez)
# DEFAULT_PASSWORD="VotreMotDePasseIci123"

# Option 2: Laisser vide pour mode sans mot de passe
DEFAULT_PASSWORD="3esMTVX4KDo4A6V7x4"

# ═══════════════════════════════════════════════════════════

# Fichier d'utilisateurs
USERS_FILE="$1"

# Mot de passe : prend l'argument en priorité, sinon DEFAULT_PASSWORD
if [[ -n "$2" ]]; then
    GLOBAL_PASSWORD="$2"
else
    GLOBAL_PASSWORD="${DEFAULT_PASSWORD}"
fi

# Vérification root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Ce script doit être exécuté en tant que root${NC}"
   exit 1
fi

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Création en masse d'utilisateurs VPN         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    print_header
    echo -e "${GREEN}Usage:${NC}"
    echo "  ./vpn-bulk-create.sh <fichier_utilisateurs> [mot_de_passe_global]"
    echo ""
    echo -e "${GREEN}Formats de fichier supportés:${NC}"
    echo ""
    echo "1. Format simple (un utilisateur par ligne):"
    echo "   john_doe"
    echo "   jane_smith"
    echo "   admin_dev"
    echo ""
    echo "2. Format avec IP fixe (utilisateur:ip):"
    echo "   john_doe:10.8.0.100"
    echo "   jane_smith:10.8.0.101"
    echo "   admin_dev:10.8.0.102"
    echo ""
    echo -e "${GREEN}Exemples:${NC}"
    echo "  ./vpn-bulk-create.sh users.txt"
    echo "  ./vpn-bulk-create.sh users.txt MonMotDePasse123"
    echo ""
    echo -e "${YELLOW}Note: Si mot_de_passe_global n'est pas fourni, les certificats seront sans mot de passe${NC}"
    echo ""
}

# Vérification des arguments
if [[ -z "$USERS_FILE" ]]; then
    show_help
    exit 1
fi

if [[ ! -f "$USERS_FILE" ]]; then
    echo -e "${RED}❌ Fichier '$USERS_FILE' introuvable${NC}"
    exit 1
fi

# Préparation de l'environnement
setup_environment() {
    echo -e "${BLUE}🔧 Préparation de l'environnement...${NC}"

    # Créer le répertoire clients si inexistant
    if [[ ! -d "$CLIENT_DIR" ]]; then
        echo -e "${YELLOW}   ├─ Création du répertoire clients: $CLIENT_DIR${NC}"
        mkdir -p $CLIENT_DIR
        chmod 755 $CLIENT_DIR
        chown www-data:www-data $CLIENT_DIR
        echo -e "${GREEN}   └─ Répertoire clients créé${NC}"
    else
        echo -e "${GREEN}   ├─ Répertoire clients existe déjà: $CLIENT_DIR${NC}"
        # Vérifier les permissions
        chmod 755 $CLIENT_DIR
        chown www-data:www-data $CLIENT_DIR
    fi

    # Créer le répertoire CCD pour IPs fixes si inexistant
    if [[ ! -d "$CCD_DIR" ]]; then
        echo -e "${YELLOW}   ├─ Création du répertoire CCD: $CCD_DIR${NC}"
        mkdir -p $CCD_DIR
        echo -e "${GREEN}   └─ Répertoire CCD créé${NC}"
    else
        echo -e "${GREEN}   ├─ Répertoire CCD existe déjà: $CCD_DIR${NC}"
    fi

    # Vérifier que tls-crypt.key existe
    if [[ ! -f "$OPENVPN_DIR/tls-crypt.key" ]]; then
        echo -e "${YELLOW}   ├─ tls-crypt.key introuvable, création...${NC}"
        cd $OPENVPN_DIR
        openvpn --genkey secret tls-crypt.key
        chmod 600 tls-crypt.key
        echo -e "${GREEN}   └─ tls-crypt.key créée${NC}"
    else
        echo -e "${GREEN}   ├─ tls-crypt.key existe déjà${NC}"
    fi

    # Vérifier la config serveur
    if ! grep -q "^tls-crypt" $OPENVPN_DIR/server.conf; then
        echo -e "${RED}   ├─ ⚠️  ATTENTION: Configuration serveur à mettre à jour${NC}"
        echo -e "${YELLOW}   │  Remplacez 'tls-auth ta.key 0' par 'tls-crypt tls-crypt.key'${NC}"
        echo -e "${YELLOW}   └─ Commande: nano $OPENVPN_DIR/server.conf${NC}"
    else
        echo -e "${GREEN}   ├─ Configuration serveur OK (tls-crypt activé)${NC}"
    fi

    # Vérifier client-config-dir
    if ! grep -q "^client-config-dir" $OPENVPN_DIR/server.conf; then
        echo -e "${YELLOW}   ├─ Ajout de 'client-config-dir ccd' dans server.conf${NC}"
        echo "client-config-dir ccd" >> $OPENVPN_DIR/server.conf
        echo -e "${GREEN}   └─ client-config-dir activé${NC}"
    else
        echo -e "${GREEN}   ├─ client-config-dir déjà configuré${NC}"
    fi

    echo ""
    echo -e "${GREEN}✅ Environnement prêt${NC}"
    echo ""
}

# Générer le fichier .ovpn complet (avec certificats inclus)
generate_ovpn_unified() {
    local CLIENT_NAME=$1
    local CLIENT_PATH=$CLIENT_DIR/$CLIENT_NAME

    cat > $CLIENT_PATH/${CLIENT_NAME}.ovpn <<EOF
# Configuration OpenVPN Client
# Utilisateur: $CLIENT_NAME
# Généré le: $(date)
# Serveur: $SERVER_IP

client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind

remote-cert-tls server
cipher AES-256-GCM
comp-lzo
verb 3

persist-key
persist-tun

# Certificats intégrés
<ca>
$(cat $CLIENT_PATH/ca.crt)
</ca>

<cert>
$(cat $CLIENT_PATH/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat $CLIENT_PATH/${CLIENT_NAME}.key)
</key>

<tls-crypt>
$(cat $OPENVPN_DIR/tls-crypt.key)
</tls-crypt>
EOF
}

# Configurer une IP fixe pour un client
set_fixed_ip() {
    local CLIENT_NAME=$1
    local FIXED_IP=$2

    # Calculer l'IP peer (pour la topologie net30)
    IFS='.' read -r -a ip_parts <<< "$FIXED_IP"
    last_octet=${ip_parts[3]}
    peer_octet=$((last_octet - 1))

    if [[ $peer_octet -lt 1 ]]; then
        peer_octet=$((last_octet + 1))
    fi

    peer_ip="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.$peer_octet"

    # Créer le fichier CCD
    cat > $CCD_DIR/$CLIENT_NAME <<EOF
# IP fixe pour $CLIENT_NAME
ifconfig-push $FIXED_IP $peer_ip
EOF

    echo -e "${GREEN}   ├─ IP fixe configurée: $FIXED_IP${NC}"
}

# Créer un utilisateur
create_user() {
    local USER_LINE=$1
    local CLIENT_NAME=""
    local FIXED_IP=""

    # Parser le format utilisateur:ip si présent
    if [[ $USER_LINE == *":"* ]]; then
        CLIENT_NAME=$(echo $USER_LINE | cut -d: -f1)
        FIXED_IP=$(echo $USER_LINE | cut -d: -f2)
    else
        CLIENT_NAME=$USER_LINE
    fi

    # Nettoyer les espaces et caractères invisibles
    CLIENT_NAME=$(echo $CLIENT_NAME | xargs | tr -d '\r')
    FIXED_IP=$(echo $FIXED_IP | xargs | tr -d '\r')

    # Ignorer les lignes vides ou commentaires
    if [[ -z "$CLIENT_NAME" || "$CLIENT_NAME" == \#* ]]; then
        echo -e "${YELLOW}   ⊘ Ligne ignorée (vide ou commentaire)${NC}"
        return
    fi

    echo -e "${BLUE}👤 Création de: ${GREEN}$CLIENT_NAME${NC}"

    # Vérifier si existe déjà
    if [[ -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" ]]; then
        echo -e "${YELLOW}   ⚠️  Utilisateur existe déjà, ignoré${NC}"
        return
    fi

    # Créer le répertoire client
    mkdir -p $CLIENT_DIR/$CLIENT_NAME
    chmod 755 $CLIENT_DIR/$CLIENT_NAME

    cd $EASYRSA_DIR

    # Génération du certificat
    if [[ -n "$GLOBAL_PASSWORD" ]]; then
        # Avec mot de passe (nécessite expect pour automatiser)
        echo -e "${YELLOW}   ├─ Génération avec mot de passe protégé...${NC}"
        expect << EOF
set timeout -1
spawn ./easyrsa build-client-full $CLIENT_NAME
expect "Enter PEM pass phrase:"
send "$GLOBAL_PASSWORD\r"
expect "Verifying - Enter PEM pass phrase:"
send "$GLOBAL_PASSWORD\r"
expect eof
EOF
    else
        # Sans mot de passe
        echo -e "${YELLOW}   ├─ Génération sans mot de passe (nopass)...${NC}"
        ./easyrsa build-client-full $CLIENT_NAME nopass 2>&1 | grep -v "^$" || true
    fi

    # Copier les certificats
    cp pki/ca.crt $CLIENT_DIR/$CLIENT_NAME/
    cp pki/issued/${CLIENT_NAME}.crt $CLIENT_DIR/$CLIENT_NAME/
    cp pki/private/${CLIENT_NAME}.key $CLIENT_DIR/$CLIENT_NAME/

    # Générer le fichier .ovpn unifié
    generate_ovpn_unified $CLIENT_NAME

    # Configurer IP fixe si spécifiée
    if [[ -n "$FIXED_IP" ]]; then
        set_fixed_ip $CLIENT_NAME $FIXED_IP
    fi

    # Créer une archive téléchargeable
    cd $CLIENT_DIR
    tar -czf ${CLIENT_NAME}.tar.gz $CLIENT_NAME/
    chmod 644 ${CLIENT_NAME}.tar.gz

    echo -e "${GREEN}   ✅ Utilisateur créé avec succès${NC}"
    echo -e "${BLUE}   └─ Fichier: $CLIENT_DIR/$CLIENT_NAME/${CLIENT_NAME}.ovpn${NC}"
    echo ""
}

# Fonction principale
main() {
    print_header

    # Vérifier que GLOBAL_PASSWORD n'est pas vide ET existe
    if [[ -n "${GLOBAL_PASSWORD:-}" && "$GLOBAL_PASSWORD" != "" ]]; then
        echo -e "${GREEN}🔐 Mot de passe global: ${YELLOW}[ACTIVÉ]${NC}"
        # Vérifier si expect est installé
        if ! command -v expect &> /dev/null; then
            echo -e "${YELLOW}⚠️  Installation de 'expect' nécessaire pour les mots de passe...${NC}"
            apt update && apt install -y expect
        fi
    else
        echo -e "${YELLOW}🔓 Mode sans mot de passe (nopass)${NC}"
        GLOBAL_PASSWORD=""  # Force à vide
    fi
    echo ""

    setup_environment

    echo -e "${BLUE}📋 Lecture du fichier d'utilisateurs: ${GREEN}$USERS_FILE${NC}"
    echo ""

    # Vérifier que le fichier est lisible
    if [[ ! -r "$USERS_FILE" ]]; then
        echo -e "${RED}❌ Erreur: Impossible de lire le fichier $USERS_FILE${NC}"
        exit 1
    fi

    local COUNT=0
    local SUCCESS=0
    local line

    # Lecture du fichier ligne par ligne
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((COUNT++))
        echo -e "${BLUE}📝 Traitement de l'utilisateur $COUNT...${NC}"
        if create_user "$line"; then
            ((SUCCESS++))
        fi
    done < "$USERS_FILE"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              GÉNÉRATION TERMINÉE               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📊 Statistiques:${NC}"
    echo -e "   └─ Utilisateurs traités: $COUNT"
    echo -e "   └─ Créations réussies: $SUCCESS"
    echo ""
    echo -e "${BLUE}📁 Fichiers disponibles dans:${NC}"
    echo -e "   └─ ${GREEN}$CLIENT_DIR/${NC}"
    echo ""
    echo -e "${BLUE}🌐 Accès web (si serveur web configuré):${NC}"
    echo -e "   └─ ${GREEN}http://$SERVER_IP/vpn-clients/${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  N'oubliez pas de redémarrer OpenVPN:${NC}"
    echo -e "   └─ ${BLUE}systemctl restart openvpn@server.service${NC}"
    echo ""
}

# Exécution
main
