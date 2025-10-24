#!/bin/bash

# Script d'administration OpenVPN
# Interface complète de gestion

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
EASYRSA_DIR="/etc/openvpn/easy-rsa"
OPENVPN_DIR="/etc/openvpn"
CLIENT_DIR="/var/www/html/vpn-clients"
CCD_DIR="/etc/openvpn/ccd"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "N/A")

# Vérification root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Ce script doit être exécuté en tant que root${NC}"
   exit 1
fi

# Header
print_header() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                           ║${NC}"
    echo -e "${CYAN}║         🔐 PANNEAU D'ADMINISTRATION OPENVPN 🔐           ║${NC}"
    echo -e "${CYAN}║                                                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}  Serveur VPN: ${GREEN}$SERVER_IP${NC}"
    echo ""
}

# Menu principal
show_menu() {
    echo -e "${GREEN}╔══════════════════ MENU PRINCIPAL ═══════════════════════╗${NC}"
    echo -e "${GREEN}║                                                         ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}1.${NC} 📋 Lister tous les utilisateurs                   ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}2.${NC} 👥 Voir les utilisateurs connectés                ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}3.${NC} ➕ Ajouter un nouvel utilisateur                  ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}4.${NC} 🗑️  Supprimer un utilisateur (complet)            ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}5.${NC} 📊 Statistiques du serveur VPN                    ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}6.${NC} 📄 Voir les logs OpenVPN                          ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}7.${NC} 🔄 Redémarrer OpenVPN                             ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}8.${NC} 📦 Exporter la configuration d'un utilisateur     ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}9.${NC} 🌐 Gérer les IPs fixes                           ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}10.${NC} 🔧 Backup & Restauration                         ${GREEN}║${NC}"
    echo -e "${GREEN}║  ${YELLOW}0.${NC} 🚪 Quitter                                        ${GREEN}║${NC}"
    echo -e "${GREEN}║                                                         ║${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${CYAN}Choisissez une option [0-11]: ${NC}"
}

# 1. Lister tous les utilisateurs
list_all_users() {
    print_header
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📋 LISTE DE TOUS LES UTILISATEURS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    cd $EASYRSA_DIR

    if [[ ! -d "pki/issued" ]]; then
        echo -e "${YELLOW}⚠️  Aucun utilisateur trouvé${NC}"
        return
    fi

    local COUNT=0
    local ACTIVE=0
    local REVOKED=0

    printf "${CYAN}%-5s %-25s %-15s %-15s${NC}\n" "N°" "NOM UTILISATEUR" "STATUT" "IP FIXE"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

    for cert in pki/issued/*.crt; do
        if [[ -f "$cert" && "$cert" != *"server.crt"* ]]; then
            CLIENT=$(basename $cert .crt)
            ((COUNT++))

            # Vérifier si révoqué
            if grep -q "^R.*CN=$CLIENT" pki/index.txt 2>/dev/null; then
                STATUS="${RED}RÉVOQUÉ${NC}"
                ((REVOKED++))
            else
                STATUS="${GREEN}ACTIF${NC}"
                ((ACTIVE++))
            fi

            # Vérifier IP fixe
            if [[ -f "$CCD_DIR/$CLIENT" ]]; then
                FIXED_IP=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT" | awk '{print $2}')
                IP_INFO="${YELLOW}$FIXED_IP${NC}"
            else
                IP_INFO="${CYAN}Dynamique${NC}"
            fi

            printf "%-5s %-25s %-25b %-20b\n" "$COUNT" "$CLIENT" "$STATUS" "$IP_INFO"
        fi
    done

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Total: ${CYAN}$COUNT${GREEN} utilisateurs | Actifs: ${GREEN}$ACTIVE${NC} | Révoqués: ${RED}$REVOKED${NC}"
    echo ""
}

# 2. Voir les utilisateurs connectés
show_connected_users() {
    print_header
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}👥 UTILISATEURS ACTUELLEMENT CONNECTÉS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ ! -f "$OPENVPN_DIR/openvpn-status.log" ]]; then
        echo -e "${RED}❌ Fichier de statut introuvable${NC}"
        return
    fi

    printf "${CYAN}%-20s %-15s %-25s %-15s${NC}\n" "UTILISATEUR" "IP VPN" "IP RÉELLE" "CONNECTÉ DEPUIS"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

    local CONNECTED=0

    # Stocker le contenu du fichier de statut pour éviter de le lire plusieurs fois
    local LOG_CONTENT
    LOG_CONTENT=$(cat "$OPENVPN_DIR/openvpn-status.log")

    while IFS=',' read -r name real_addr bytes_recv bytes_sent connected_since; do
        # On ne traite que les lignes qui sont dans la CLIENT LIST
        if [[ "$name" != "Common Name" && "$name" != "ROUTING TABLE" && ! -z "$name" ]]; then

            # Correction de la logique : Extraire l'IP VPN de la table de routage
            # On cherche le Common Name ($name) dans la section ROUTING TABLE
            vpn_ip=$(echo "$LOG_CONTENT" | grep -A 100 "ROUTING TABLE" | grep "$name," | head -1 | cut -d',' -f1)

            # Formater la date
            connect_time=$(echo $connected_since | cut -d' ' -f1-2)

            printf "%-20s %-15s %-25s %-15s\n" "$name" "${vpn_ip:-N/A}" "$real_addr" "$connect_time"
            ((CONNECTED++))
        fi
    done < <(echo "$LOG_CONTENT" | sed -n '/^Common Name,Real Address/,/^ROUTING TABLE/p' | grep -v "^ROUTING TABLE" | grep -v "^Common Name")

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

    if [[ $CONNECTED -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Aucun utilisateur connecté actuellement${NC}"
    else
        echo -e "${GREEN}✅ $CONNECTED utilisateur(s) connecté(s)${NC}"
    fi
    echo ""
}

# Fonction pour vérifier si une IP est valide et disponible
check_ip_validity() {
    local requested_ip=$1
    local client_name=$2  # Pour exclure lors de la modification

    # Extraire le dernier octet
    IFS='.' read -r -a ip_parts <<< "$requested_ip"
    local last_octet=${ip_parts[3]}

    # Vérifier les IPs réservées
    if [[ $last_octet -eq 0 || $last_octet -eq 1 || $last_octet -eq 2 || $last_octet -eq 255 ]]; then
        echo "RESERVED"
        return 1
    fi

    # Calculer le peer IP (pour le /30)
    local peer_octet
    if [[ $((last_octet % 2)) -eq 0 ]]; then
        # IP paire → peer est +1
        peer_octet=$((last_octet + 1))
    else
        # IP impaire → peer est -1
        peer_octet=$((last_octet - 1))
    fi

    local peer_ip="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.$peer_octet"

    # Vérifier si l'IP ou son peer sont déjà utilisés
    for ccd_file in $CCD_DIR/*; do
        if [[ -f "$ccd_file" ]]; then
            local other_client=$(basename "$ccd_file")

            # Ignorer le client actuel (pour modification)
            if [[ -n "$client_name" && "$other_client" == "$client_name" ]]; then
                continue
            fi

            local other_ip=$(grep "ifconfig-push" "$ccd_file" | awk '{print $2}')
            local other_peer=$(grep "ifconfig-push" "$ccd_file" | awk '{print $3}')

            # Vérifier collision avec l'IP demandée ou son peer
            if [[ "$other_ip" == "$requested_ip" ]]; then
                echo "USED_BY:$other_client:CLIENT"
                return 1
            fi

            if [[ "$other_peer" == "$requested_ip" ]]; then
                echo "USED_BY:$other_client:PEER"
                return 1
            fi

            # Vérifier collision inverse (notre peer avec leur IP)
            if [[ "$other_ip" == "$peer_ip" ]]; then
                echo "PEER_CONFLICT:$other_client"
                return 1
            fi

            if [[ "$other_peer" == "$peer_ip" ]]; then
                echo "PEER_CONFLICT:$other_client"
                return 1
            fi
        fi
    done

    echo "OK:$peer_ip"
    return 0
}
# 3. Ajouter un utilisateur
add_user() {
    print_header
    echo -e "${GREEN}➕ AJOUTER UN NOUVEL UTILISATEUR${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    read -p "Nom d'utilisateur: " CLIENT_NAME

    # Validation
    if [[ -z "$CLIENT_NAME" ]]; then
        echo -e "${RED}❌ Nom d'utilisateur vide${NC}"
        return
    fi

    # Vérifier si existe déjà
    if [[ -f "$EASYRSA_DIR/pki/issued/${CLIENT_NAME}.crt" ]]; then
        echo -e "${RED}❌ L'utilisateur '$CLIENT_NAME' existe déjà${NC}"
        return
    fi

    # Demander mot de passe
    echo ""
    read -p "Protéger avec un mot de passe ? (o/N): " -n 1 -r USE_PASS
    echo ""

    # Demander IP fixe
    read -p "Assigner une IP fixe ? (o/N): " -n 1 -r USE_FIXED_IP
    echo ""

    FIXED_IP=""
    if [[ $USE_FIXED_IP =~ ^[Oo]$ ]]; then
        # Afficher les IPs déjà utilisées avec leurs plages /30
        echo -e "${CYAN}IPs fixes actuellement utilisées (avec leur peer):${NC}"
        local has_fixed_ips=false
        for ccd_file in $CCD_DIR/*; do
            if [[ -f "$ccd_file" ]]; then
                OTHER_CLIENT=$(basename "$ccd_file")
                OTHER_IP=$(grep "ifconfig-push" "$ccd_file" | awk '{print $2}')
                OTHER_PEER=$(grep "ifconfig-push" "$ccd_file" | awk '{print $3}')
                echo -e "  ${YELLOW}$OTHER_CLIENT${NC} → $OTHER_IP (peer: $OTHER_PEER)"
                has_fixed_ips=true
            fi
        done

        if [[ "$has_fixed_ips" == false ]]; then
            echo -e "  ${YELLOW}Aucune${NC}"
        fi

        echo ""
        echo -e "${CYAN}💡 Règles pour les IPs fixes:${NC}"
        echo -e "  ${YELLOW}•${NC} Utilisez des paires d'IPs (ex: .4/.5, .8/.9, .12/.13, .16/.17...)"
        echo -e "  ${YELLOW}•${NC} Évitez .0, .1, .2, .255"
        echo -e "  ${YELLOW}•${NC} Suggestions libres: .4, .8, .12, .16, .20, .24..."
        echo ""

        while true; do
            read -p "Adresse IP (ex: 10.8.0.4): " FIXED_IP

            # Validation format
            if [[ ! $FIXED_IP =~ ^10\.8\.0\.[0-9]+$ ]]; then
                echo -e "${RED}❌ Format invalide (attendu: 10.8.0.X)${NC}"
                read -p "Réessayer ? (o/N): " -n 1 -r RETRY
                echo ""
                if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                    FIXED_IP=""
                    break
                fi
                continue
            fi

            # Vérifier la validité
            result=$(check_ip_validity "$FIXED_IP" "")
            status=$(echo "$result" | cut -d':' -f1)

            case $status in
                "RESERVED")
                    echo -e "${RED}❌ IP réservée (.0, .1, .2, .255 ne peuvent pas être utilisées)${NC}"
                    ;;
                "USED_BY")
                    other_client=$(echo "$result" | cut -d':' -f2)
                    usage_type=$(echo "$result" | cut -d':' -f3)
                    if [[ "$usage_type" == "CLIENT" ]]; then
                        echo -e "${RED}❌ Cette IP est déjà utilisée par '$other_client'${NC}"
                    else
                        echo -e "${RED}❌ Cette IP est le peer de '$other_client'${NC}"
                    fi
                    ;;
                "PEER_CONFLICT")
                    other_client=$(echo "$result" | cut -d':' -f2)
                    echo -e "${RED}❌ Le peer de cette IP (.$(echo $FIXED_IP | cut -d'.' -f4)) est déjà utilisé par '$other_client'${NC}"
                    echo -e "${YELLOW}   Les IPs doivent être en paires /30 non chevauchantes${NC}"
                    ;;
                "OK")
                    peer_ip=$(echo "$result" | cut -d':' -f2)
                    echo -e "${GREEN}✅ IP valide: $FIXED_IP (peer: $peer_ip)${NC}"
                    break
                    ;;
            esac

            read -p "Réessayer ? (o/N): " -n 1 -r RETRY
            echo ""
            if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                FIXED_IP=""
                break
            fi
        done
    fi

    echo ""
    echo -e "${YELLOW}🔐 Création de l'utilisateur '$CLIENT_NAME'...${NC}"

    cd $EASYRSA_DIR

    # Génération du certificat
    if [[ $USE_PASS =~ ^[Oo]$ ]]; then
        ./easyrsa build-client-full $CLIENT_NAME
    else
        ./easyrsa build-client-full $CLIENT_NAME nopass
    fi

    # Créer le répertoire client
    mkdir -p $CLIENT_DIR/$CLIENT_NAME

    # Copier les certificats
    cp pki/ca.crt $CLIENT_DIR/$CLIENT_NAME/
    cp pki/issued/${CLIENT_NAME}.crt $CLIENT_DIR/$CLIENT_NAME/
    cp pki/private/${CLIENT_NAME}.key $CLIENT_DIR/$CLIENT_NAME/

    # Générer le fichier .ovpn
    cat > $CLIENT_DIR/$CLIENT_NAME/${CLIENT_NAME}.ovpn <<EOF
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

<ca>
$(cat $CLIENT_DIR/$CLIENT_NAME/ca.crt)
</ca>

<cert>
$(cat $CLIENT_DIR/$CLIENT_NAME/${CLIENT_NAME}.crt)
</cert>

<key>
$(cat $CLIENT_DIR/$CLIENT_NAME/${CLIENT_NAME}.key)
</key>

<tls-crypt>
$(cat $OPENVPN_DIR/tls-crypt.key)
</tls-crypt>
EOF

    # Configurer IP fixe si demandée
    if [[ -n "$FIXED_IP" ]]; then
        result=$(check_ip_validity "$FIXED_IP" "")
        peer_ip=$(echo "$result" | cut -d':' -f2)

        echo "ifconfig-push $FIXED_IP $peer_ip" > $CCD_DIR/$CLIENT_NAME
        echo -e "${GREEN}✅ IP fixe configurée: $FIXED_IP (peer: $peer_ip)${NC}"
    fi

    # Créer l'archive
    cd $CLIENT_DIR
    tar -czf ${CLIENT_NAME}.tar.gz $CLIENT_NAME/
    chmod 644 ${CLIENT_NAME}.tar.gz

    echo ""
    echo -e "${GREEN}✅ Utilisateur '$CLIENT_NAME' créé avec succès !${NC}"
    echo -e "${CYAN}📁 Fichiers dans: $CLIENT_DIR/$CLIENT_NAME/${NC}"
    echo -e "${CYAN}📦 Archive: $CLIENT_DIR/${CLIENT_NAME}.tar.gz${NC}"

    if [[ -n "$FIXED_IP" ]]; then
        echo -e "${CYAN}🌐 IP fixe: $FIXED_IP (peer: $peer_ip)${NC}"
    fi
    echo ""
}

# 4. Supprimer un utilisateur (révocation + suppression complète)
delete_user() {
    print_header
    echo -e "${RED}🗑️  SUPPRIMER UN UTILISATEUR${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Lister les utilisateurs actifs
    echo -e "${CYAN}Utilisateurs disponibles:${NC}"
    cd $EASYRSA_DIR

    declare -a USERS
    local count=0

    for cert in pki/issued/*.crt; do
        if [[ -f "$cert" && "$cert" != *"server.crt"* ]]; then
            CLIENT=$(basename $cert .crt)
            ((count++))
            USERS[$count]=$CLIENT

            # Vérifier si révoqué
            if grep -q "^R.*CN=$CLIENT" pki/index.txt 2>/dev/null; then
                echo -e "  ${RED}$count.${NC} $CLIENT ${YELLOW}(révoqué)${NC}"
            else
                echo -e "  ${GREEN}$count.${NC} $CLIENT ${GREEN}(actif)${NC}"
            fi
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Aucun utilisateur à supprimer${NC}"
        return
    fi

    echo ""
    read -p "Numéro de l'utilisateur à supprimer (0 pour annuler): " USER_NUM

    # Validation
    if [[ -z "$USER_NUM" || "$USER_NUM" == "0" ]]; then
        echo -e "${BLUE}ℹ️  Opération annulée${NC}"
        return
    fi

    if ! [[ "$USER_NUM" =~ ^[0-9]+$ ]] || [[ $USER_NUM -lt 1 ]] || [[ $USER_NUM -gt $count ]]; then
        echo -e "${RED}❌ Numéro invalide${NC}"
        return
    fi

    CLIENT_NAME=${USERS[$USER_NUM]}

    echo ""
    echo -e "${RED}⚠️  ATTENTION: Cette action va:${NC}"
    echo -e "   ${YELLOW}1. Révoquer le certificat de '$CLIENT_NAME' (si pas déjà fait)${NC}"
    echo -e "   ${YELLOW}2. Supprimer tous les fichiers de configuration${NC}"
    echo -e "   ${YELLOW}3. Supprimer l'IP fixe (si configurée)${NC}"
    echo -e "   ${RED}4. Cette action est IRRÉVERSIBLE${NC}"
    echo ""
    read -p "Confirmer la suppression de '$CLIENT_NAME' ? (SUPPRIMER/N): " -r CONFIRM

    if [[ $CONFIRM != "SUPPRIMER" ]]; then
        echo -e "${BLUE}ℹ️  Opération annulée${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}🗑️  Suppression en cours...${NC}"

    # Révoquer si pas déjà fait
    cd $EASYRSA_DIR
    if ! grep -q "^R.*CN=$CLIENT_NAME" pki/index.txt 2>/dev/null; then
        echo -e "${YELLOW}   ├─ Révocation du certificat...${NC}"
        ./easyrsa revoke $CLIENT_NAME 2>/dev/null || true
        ./easyrsa gen-crl
        cp pki/crl.pem $OPENVPN_DIR/
        chmod 644 $OPENVPN_DIR/crl.pem
    else
        echo -e "${GREEN}   ├─ Certificat déjà révoqué${NC}"
    fi

    # Supprimer les fichiers
    if [[ -d "$CLIENT_DIR/$CLIENT_NAME" ]]; then
        echo -e "${YELLOW}   ├─ Suppression des fichiers de configuration...${NC}"
        rm -rf $CLIENT_DIR/$CLIENT_NAME
        rm -f $CLIENT_DIR/${CLIENT_NAME}.tar.gz
    fi

    # Supprimer l'IP fixe
    if [[ -f "$CCD_DIR/$CLIENT_NAME" ]]; then
        echo -e "${YELLOW}   ├─ Suppression de l'IP fixe...${NC}"
        rm -f $CCD_DIR/$CLIENT_NAME
    fi

    # Redémarrer OpenVPN
    echo -e "${YELLOW}   └─ Redémarrage d'OpenVPN...${NC}"
    systemctl restart openvpn@server.service

    echo ""
    echo -e "${GREEN}✅ Utilisateur '$CLIENT_NAME' supprimé complètement${NC}"
    echo ""
}
# 5. Statistiques
show_stats() {
    print_header
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}📊 STATISTIQUES DU SERVEUR VPN${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Comptage utilisateurs
    cd $EASYRSA_DIR
    local total=0
    local active=0
    local revoked=0

    for cert in pki/issued/*.crt; do
        if [[ -f "$cert" && "$cert" != *"server.crt"* ]]; then
            CLIENT=$(basename $cert .crt)
            ((total++))
            if grep -q "^R.*CN=$CLIENT" pki/index.txt 2>/dev/null; then
                ((revoked++))
            else
                ((active++))
            fi
        fi
    done

    # Utilisateurs connectés
    local connected=0
    if [[ -f "$OPENVPN_DIR/openvpn-status.log" ]]; then
        connected=$(grep -c "^.*,.*:[0-9]*,[0-9]*,[0-9]*," "$OPENVPN_DIR/openvpn-status.log" 2>/dev/null || echo 0)
    fi

    # Statut OpenVPN
    local vpn_status=$(systemctl is-active openvpn@server.service)
    if [[ $vpn_status == "active" ]]; then
        vpn_status_color="${GREEN}✅ Actif${NC}"
    else
        vpn_status_color="${RED}❌ Inactif${NC}"
    fi

    # Uptime
    local uptime=$(systemctl show openvpn@server.service --property=ActiveEnterTimestamp --value)

    # Interface réseau
    local tun_status=$(ip addr show tun0 2>/dev/null | grep "inet " | awk '{print $2}' || echo "N/A")

    echo -e "${CYAN}📌 Informations serveur:${NC}"
    echo -e "   Adresse IP publique: ${GREEN}$SERVER_IP${NC}"
    echo -e "   Interface VPN (tun0): ${GREEN}$tun_status${NC}"
    echo -e "   Statut OpenVPN: $vpn_status_color"
    echo ""

    echo -e "${CYAN}👥 Utilisateurs:${NC}"
    echo -e "   Total: ${CYAN}$total${NC}"
    echo -e "   Actifs: ${GREEN}$active${NC}"
    echo -e "   Révoqués: ${RED}$revoked${NC}"
    echo -e "   Connectés actuellement: ${YELLOW}$connected${NC}"
    echo ""

    echo -e "${CYAN}💾 Utilisation réseau (interface tun0):${NC}"
    if ip link show tun0 &>/dev/null; then
        local rx_bytes=$(cat /sys/class/net/tun0/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/tun0/statistics/tx_bytes 2>/dev/null || echo 0)
        local rx_mb=$((rx_bytes / 1024 / 1024))
        local tx_mb=$((tx_bytes / 1024 / 1024))
        echo -e "   Reçu: ${GREEN}${rx_mb} MB${NC}"
        echo -e "   Envoyé: ${YELLOW}${tx_mb} MB${NC}"
    else
        echo -e "   ${YELLOW}Interface tun0 non disponible${NC}"
    fi

    echo ""
    echo -e "${CYAN}⏱️  Uptime OpenVPN:${NC}"
    echo -e "   $uptime"
    echo ""
}

# 6. Voir les logs
show_logs() {
    print_header
    echo -e "${GREEN}📄 LOGS OPENVPN (50 dernières lignes)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}[Appuyez sur 'q' pour quitter, ↑↓ pour naviguer]${NC}"
    echo ""
    sleep 2

    journalctl -u openvpn@server.service -n 50 --no-pager

    echo ""
    echo -e "${YELLOW}Pour voir les logs en temps réel: journalctl -u openvpn@server.service -f${NC}"
    echo ""
}

# 7. Redémarrer OpenVPN
restart_openvpn() {
    print_header
    echo -e "${YELLOW}🔄 REDÉMARRAGE D'OPENVPN${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    read -p "Confirmer le redémarrage du serveur OpenVPN ? (o/N): " -n 1 -r CONFIRM
    echo ""

    if [[ ! $CONFIRM =~ ^[Oo]$ ]]; then
        echo -e "${BLUE}ℹ️  Opération annulée${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}🔄 Redémarrage en cours...${NC}"
    systemctl restart openvpn@server.service
    sleep 2

    if systemctl is-active --quiet openvpn@server.service; then
        echo -e "${GREEN}✅ OpenVPN redémarré avec succès${NC}"
    else
        echo -e "${RED}❌ Erreur lors du redémarrage${NC}"
        echo -e "${YELLOW}Vérifiez les logs pour plus de détails${NC}"
    fi
    echo ""
}

# 8. Exporter la configuration
export_config() {
    print_header
    echo -e "${GREEN}📦 EXPORTER LA CONFIGURATION D'UN UTILISATEUR${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    read -p "Nom de l'utilisateur: " CLIENT_NAME

    if [[ -z "$CLIENT_NAME" ]]; then
        echo -e "${RED}❌ Nom vide${NC}"
        return
    fi

    if [[ ! -d "$CLIENT_DIR/$CLIENT_NAME" ]]; then
        echo -e "${RED}❌ L'utilisateur '$CLIENT_NAME' n'existe pas ou n'a pas de fichiers${NC}"
        return
    fi

    local export_file="/tmp/${CLIENT_NAME}_vpn_$(date +%Y%m%d_%H%M%S).tar.gz"

    echo -e "${YELLOW}📦 Création de l'archive...${NC}"
    cd $CLIENT_DIR
    tar -czf $export_file $CLIENT_NAME/

    echo ""
    echo -e "${GREEN}✅ Configuration exportée avec succès !${NC}"
    echo -e "${CYAN}📁 Fichier: $export_file${NC}"
    echo ""
    echo -e "${BLUE}Pour télécharger depuis votre machine:${NC}"
    echo -e "   scp root@$SERVER_IP:$export_file ."
    echo ""
}

# 9. Gérer les IPs fixes
manage_fixed_ips() {
    print_header
    echo -e "${GREEN}🌐 GESTION DES IPs FIXES${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}Utilisateurs avec IP fixe:${NC}"
    echo ""

    declare -a FIXED_IP_USERS
    local fixed_count=0
    for ccd_file in $CCD_DIR/*; do
        if [[ -f "$ccd_file" ]]; then
            CLIENT=$(basename $ccd_file)
            FIXED_IP=$(grep "ifconfig-push" "$ccd_file" | awk '{print $2}')
            PEER_IP=$(grep "ifconfig-push" "$ccd_file" | awk '{print $3}')
            ((fixed_count++))
            FIXED_IP_USERS[$fixed_count]=$CLIENT
            echo -e "  ${GREEN}$fixed_count.${NC} $CLIENT → ${YELLOW}$FIXED_IP${NC} (peer: $PEER_IP)"
        fi
    done

    if [[ $fixed_count -eq 0 ]]; then
        echo -e "${YELLOW}  Aucune IP fixe configurée${NC}"
    fi

    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${YELLOW}1.${NC} Ajouter une IP fixe à un utilisateur"
    echo -e "  ${YELLOW}2.${NC} Modifier une IP fixe"
    echo -e "  ${YELLOW}3.${NC} Supprimer une IP fixe"
    echo -e "  ${YELLOW}0.${NC} Retour"
    echo ""
    read -p "Choix: " -n 1 -r CHOICE
    echo ""

    case $CHOICE in
        1)
            echo ""
            echo -e "${CYAN}Utilisateurs disponibles:${NC}"

            declare -a ALL_USERS
            local count=0
            cd $EASYRSA_DIR

            for cert in pki/issued/*.crt; do
                if [[ -f "$cert" && "$cert" != *"server.crt"* ]]; then
                    CLIENT=$(basename $cert .crt)

                    # Vérifier si pas révoqué
                    if ! grep -q "^R.*CN=$CLIENT" pki/index.txt 2>/dev/null; then
                        ((count++))
                        ALL_USERS[$count]=$CLIENT

                        # Vérifier si a déjà une IP fixe
                        if [[ -f "$CCD_DIR/$CLIENT" ]]; then
                            CURRENT_IP=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT" | awk '{print $2}')
                            CURRENT_PEER=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT" | awk '{print $3}')
                            echo -e "  ${YELLOW}$count.${NC} $CLIENT ${CYAN}(a déjà: $CURRENT_IP / $CURRENT_PEER)${NC}"
                        else
                            echo -e "  ${GREEN}$count.${NC} $CLIENT"
                        fi
                    fi
                fi
            done

            if [[ $count -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  Aucun utilisateur actif${NC}"
                return
            fi

            echo ""
            read -p "Numéro de l'utilisateur (0 pour annuler): " USER_NUM

            if [[ -z "$USER_NUM" || "$USER_NUM" == "0" ]]; then
                echo -e "${BLUE}ℹ️  Opération annulée${NC}"
                return
            fi

            if ! [[ "$USER_NUM" =~ ^[0-9]+$ ]] || [[ $USER_NUM -lt 1 ]] || [[ $USER_NUM -gt $count ]]; then
                echo -e "${RED}❌ Numéro invalide${NC}"
                return
            fi

            CLIENT_NAME=${ALL_USERS[$USER_NUM]}

            echo ""
            echo -e "${CYAN}💡 Règles pour les IPs fixes:${NC}"
            echo -e "  ${YELLOW}•${NC} Utilisez des paires d'IPs (ex: .4/.5, .8/.9, .12/.13...)"
            echo -e "  ${YELLOW}•${NC} Évitez .0, .1, .2, .255"
            echo ""

            while true; do
                read -p "Adresse IP (ex: 10.8.0.4): " FIXED_IP

                if [[ ! $FIXED_IP =~ ^10\.8\.0\.[0-9]+$ ]]; then
                    echo -e "${RED}❌ Format invalide (attendu: 10.8.0.X)${NC}"
                    read -p "Réessayer ? (o/N): " -n 1 -r RETRY
                    echo ""
                    if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                        return
                    fi
                    continue
                fi

                # Vérifier la validité avec la nouvelle fonction
                result=$(check_ip_validity "$FIXED_IP" "$CLIENT_NAME")
                status=$(echo "$result" | cut -d':' -f1)

                case $status in
                    "RESERVED")
                        echo -e "${RED}❌ IP réservée (.0, .1, .2, .255)${NC}"
                        ;;
                    "USED_BY")
                        other_client=$(echo "$result" | cut -d':' -f2)
                        usage_type=$(echo "$result" | cut -d':' -f3)
                        if [[ "$usage_type" == "CLIENT" ]]; then
                            echo -e "${RED}❌ IP déjà utilisée par '$other_client'${NC}"
                        else
                            echo -e "${RED}❌ IP est le peer de '$other_client'${NC}"
                        fi
                        ;;
                    "PEER_CONFLICT")
                        other_client=$(echo "$result" | cut -d':' -f2)
                        echo -e "${RED}❌ Conflit de peer avec '$other_client'${NC}"
                        ;;
                    "OK")
                        peer_ip=$(echo "$result" | cut -d':' -f2)
                        echo "ifconfig-push $FIXED_IP $peer_ip" > $CCD_DIR/$CLIENT_NAME
                        echo -e "${GREEN}✅ IP fixe $FIXED_IP (peer: $peer_ip) assignée à $CLIENT_NAME${NC}"
                        echo -e "${YELLOW}⚠️  Redémarrez OpenVPN pour appliquer (option 7)${NC}"
                        return
                        ;;
                esac

                read -p "Réessayer ? (o/N): " -n 1 -r RETRY
                echo ""
                if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                    return
                fi
            done
            ;;
        2)
            if [[ $fixed_count -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  Aucune IP fixe à modifier${NC}"
                return
            fi

            echo ""
            read -p "Numéro de l'utilisateur (0 pour annuler): " USER_NUM

            if [[ -z "$USER_NUM" || "$USER_NUM" == "0" ]]; then
                echo -e "${BLUE}ℹ️  Opération annulée${NC}"
                return
            fi

            if ! [[ "$USER_NUM" =~ ^[0-9]+$ ]] || [[ $USER_NUM -lt 1 ]] || [[ $USER_NUM -gt $fixed_count ]]; then
                echo -e "${RED}❌ Numéro invalide${NC}"
                return
            fi

            CLIENT_NAME=${FIXED_IP_USERS[$USER_NUM]}

            OLD_IP=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT_NAME" | awk '{print $2}')
            OLD_PEER=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT_NAME" | awk '{print $3}')
            echo -e "${CYAN}IP actuelle de $CLIENT_NAME: $OLD_IP (peer: $OLD_PEER)${NC}"
            echo ""

            while true; do
                read -p "Nouvelle IP (ex: 10.8.0.4): " FIXED_IP

                if [[ ! $FIXED_IP =~ ^10\.8\.0\.[0-9]+$ ]]; then
                    echo -e "${RED}❌ Format invalide${NC}"
                    read -p "Réessayer ? (o/N): " -n 1 -r RETRY
                    echo ""
                    if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                        return
                    fi
                    continue
                fi

                result=$(check_ip_validity "$FIXED_IP" "$CLIENT_NAME")
                status=$(echo "$result" | cut -d':' -f1)

                case $status in
                    "RESERVED")
                        echo -e "${RED}❌ IP réservée${NC}"
                        ;;
                    "USED_BY")
                        other_client=$(echo "$result" | cut -d':' -f2)
                        echo -e "${RED}❌ IP utilisée par '$other_client'${NC}"
                        ;;
                    "PEER_CONFLICT")
                        other_client=$(echo "$result" | cut -d':' -f2)
                        echo -e "${RED}❌ Conflit de peer avec '$other_client'${NC}"
                        ;;
                    "OK")
                        peer_ip=$(echo "$result" | cut -d':' -f2)
                        echo "ifconfig-push $FIXED_IP $peer_ip" > $CCD_DIR/$CLIENT_NAME
                        echo -e "${GREEN}✅ IP modifiée pour $CLIENT_NAME: $OLD_IP → $FIXED_IP (peer: $peer_ip)${NC}"
                        echo -e "${YELLOW}⚠️  Redémarrez OpenVPN pour appliquer (option 7)${NC}"
                        return
                        ;;
                esac

                read -p "Réessayer ? (o/N): " -n 1 -r RETRY
                echo ""
                if [[ ! $RETRY =~ ^[Oo]$ ]]; then
                    return
                fi
            done
            ;;
        3)
            if [[ $fixed_count -eq 0 ]]; then
                echo -e "${YELLOW}⚠️  Aucune IP fixe à supprimer${NC}"
                return
            fi

            echo ""
            read -p "Numéro de l'utilisateur (0 pour annuler): " USER_NUM

            if [[ -z "$USER_NUM" || "$USER_NUM" == "0" ]]; then
                echo -e "${BLUE}ℹ️  Opération annulée${NC}"
                return
            fi

            if ! [[ "$USER_NUM" =~ ^[0-9]+$ ]] || [[ $USER_NUM -lt 1 ]] || [[ $USER_NUM -gt $fixed_count ]]; then
                echo -e "${RED}❌ Numéro invalide${NC}"
                return
            fi

            CLIENT_NAME=${FIXED_IP_USERS[$USER_NUM]}

            OLD_IP=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT_NAME" | awk '{print $2}')
            OLD_PEER=$(grep "ifconfig-push" "$CCD_DIR/$CLIENT_NAME" | awk '{print $3}')
            rm -f $CCD_DIR/$CLIENT_NAME

            echo -e "${GREEN}✅ IP fixe $OLD_IP/$OLD_PEER supprimée pour $CLIENT_NAME${NC}"
            echo -e "${YELLOW}⚠️  Redémarrez OpenVPN pour appliquer (option 7)${NC}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Option invalide${NC}"
            ;;
    esac

    echo ""
}
# 10. Backup & Restauration
backup_restore() {
    print_header
    echo -e "${GREEN}🔧 BACKUP & RESTAURATION${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${CYAN}Options:${NC}"
    echo -e "  ${YELLOW}1.${NC} Créer un backup complet"
    echo -e "  ${YELLOW}2.${NC} Restaurer depuis un backup"
    echo -e "  ${YELLOW}3.${NC} Lister les backups disponibles"
    echo -e "  ${YELLOW}0.${NC} Retour"
    echo ""
    read -p "Choix: " -n 1 -r CHOICE
    echo ""

    local BACKUP_DIR="/root/openvpn-backups"
    mkdir -p $BACKUP_DIR

    case $CHOICE in
        1)
            echo ""
            local backup_name="openvpn_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            local backup_path="$BACKUP_DIR/$backup_name"

            echo -e "${YELLOW}📦 Création du backup...${NC}"

            tar -czf $backup_path \
                $OPENVPN_DIR/server.conf \
                $OPENVPN_DIR/ca.crt \
                $OPENVPN_DIR/server.crt \
                $OPENVPN_DIR/server.key \
                $OPENVPN_DIR/dh.pem \
                $OPENVPN_DIR/tls-crypt.key \
                $OPENVPN_DIR/crl.pem \
                $OPENVPN_DIR/ipp.txt \
                $EASYRSA_DIR/pki \
                $CCD_DIR \
                $CLIENT_DIR 2>/dev/null

            echo ""
            echo -e "${GREEN}✅ Backup créé avec succès !${NC}"
            echo -e "${CYAN}📁 Fichier: $backup_path${NC}"
            echo -e "${CYAN}📊 Taille: $(du -h $backup_path | cut -f1)${NC}"
            echo ""
            echo -e "${BLUE}Pour télécharger:${NC}"
            echo -e "   scp root@$SERVER_IP:$backup_path ."
            ;;
        2)
            echo ""
            echo -e "${RED}⚠️  ATTENTION: La restauration va écraser la configuration actuelle${NC}"
            read -p "Chemin du fichier de backup: " BACKUP_FILE

            if [[ ! -f "$BACKUP_FILE" ]]; then
                echo -e "${RED}❌ Fichier introuvable${NC}"
                return
            fi

            read -p "Confirmer la restauration ? (oui/N): " CONFIRM
            if [[ $CONFIRM != "oui" ]]; then
                echo -e "${BLUE}ℹ️  Opération annulée${NC}"
                return
            fi

            echo -e "${YELLOW}🔄 Restauration en cours...${NC}"

            # Arrêter OpenVPN
            systemctl stop openvpn@server.service

            # Extraire le backup
            tar -xzf $BACKUP_FILE -C /

            # Redémarrer OpenVPN
            systemctl start openvpn@server.service

            echo ""
            echo -e "${GREEN}✅ Restauration terminée${NC}"
            ;;
        3)
            echo ""
            echo -e "${CYAN}Backups disponibles:${NC}"
            echo ""

            local count=0
            for backup in $BACKUP_DIR/*.tar.gz; do
                if [[ -f "$backup" ]]; then
                    ((count++))
                    local size=$(du -h "$backup" | cut -f1)
                    local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
                    echo -e "  ${GREEN}$count.${NC} $(basename $backup)"
                    echo -e "     ${CYAN}Taille: $size | Date: $date${NC}"
                fi
            done

            if [[ $count -eq 0 ]]; then
                echo -e "${YELLOW}  Aucun backup trouvé${NC}"
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Option invalide${NC}"
            ;;
    esac

    echo ""
}

# Fonction pause
pause() {
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
}

# Boucle principale
main() {
    while true; do
        print_header
        show_menu
        read -r choice

        case $choice in
            1)
                list_all_users
                pause
                ;;
            2)
                show_connected_users
                pause
                ;;
            3)
                add_user
                pause
                ;;

            4)
                delete_user
                pause
                ;;
            5)
                show_stats
                pause
                ;;
            6)
                show_logs
                pause
                ;;
            7)
                restart_openvpn
                pause
                ;;
            8)
                export_config
                pause
                ;;
            9)
                manage_fixed_ips
                pause
                ;;
            10)
                backup_restore
                pause
                ;;
            0)
                clear
                echo -e "${GREEN}✅ Au revoir !${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Option invalide${NC}"
                sleep 1
                ;;
        esac
    done
}

# Lancement
main
