#!/bin/bash
# Script de réinitialisation et configuration UFW
# Auteur: Configuration sécurisée avec VPN
# Date: 2025
# Exécuter avec: sudo bash reset-ufw-secure.sh

set -e  # Arrêter en cas d'erreur

echo "🔥 RESET ET RECONFIGURATION UFW - CONFIGURATION SÉCURISÉE"
echo "=========================================================="
echo ""
echo "Configuration prévue :"
echo "  ✓ Allow complet : lo, tun0, 154.120.176.213, 157.173.104.204"
echo "  ✓ Services publics : Web, Mail, FTP, Jitsi, Docker apps"
echo "  ✓ Services bloqués : BDD, TURN/STUN, Admin (Webmin, Jupyter, Glances)"
echo ""

# Demander confirmation
read -p "⚠️  ATTENTION : Ce script va RÉINITIALISER complètement UFW. Continuer ? (oui/non) : " confirm
if [ "$confirm" != "oui" ]; then
    echo "❌ Annulé par l'utilisateur"
    exit 1
fi

echo ""
echo "🔧 Sauvegarde de la config actuelle..."
ufw status numbered > /root/ufw-backup-$(date +%Y%m%d-%H%M%S).txt
echo "   💾 Sauvegarde créée dans /root/"

echo ""
echo "📍 Étape 1/18 : Désactivation et reset UFW..."
ufw --force disable
ufw --force reset
echo "   ✅ UFW réinitialisé"

echo ""
echo "📍 Étape 2/18 : Configuration des politiques par défaut..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed
echo "   ✅ Politiques par défaut configurées"

echo ""
echo "📍 Étape 3/18 : Allow COMPLET sur localhost (lo)..."
ufw allow in on lo comment 'Allow all on localhost'
ufw allow out on lo
echo "   ✅ Localhost (127.0.0.1) totalement ouvert"

echo ""
echo "📍 Étape 4/18 : Allow COMPLET sur VPN OpenVPN (tun0)..."
ufw allow in on tun0 comment 'Allow all on VPN'
ufw allow out on tun0
echo "   ✅ Interface VPN (tun0) totalement ouverte"

echo ""
echo "📍 Étape 5/18 : Configuration des IPs de confiance (accès TOTAL)..."
ufw allow from 154.120.176.213 comment 'IP garde-fou 1 - Acces total'
ufw allow from 157.173.104.204 comment 'IP garde-fou 2 - Acces total'
echo "   ✅ 2 IPs garde-fous configurées avec accès complet"

echo ""
echo "📍 Étape 6/18 : Services WEB publics..."
ufw allow 80/tcp comment 'HTTP - Apache'
ufw allow 443/tcp comment 'HTTPS - Apache'
echo "   ✅ Ports web 80 et 443 ouverts"

echo ""
echo "📍 Étape 7/18 : SSH (port custom 49521) - VPN/IPs uniquement..."
ufw deny 49521/tcp comment 'SSH - Deny public, allow via VPN/IPs'
echo "   ✅ SSH bloqué en public (accessible via VPN et IPs garde-fous)"

echo ""
echo "📍 Étape 8/18 : Services MAIL publics..."
ufw allow 25/tcp comment 'SMTP - Postfix'
ufw allow 587/tcp comment 'SMTP Submission - Postfix'
ufw allow 465/tcp comment 'SMTPS - Postfix'
ufw allow 110/tcp comment 'POP3 - Dovecot'
ufw allow 143/tcp comment 'IMAP - Dovecot'
ufw allow 993/tcp comment 'IMAPS - Dovecot'
ufw allow 995/tcp comment 'POP3S - Dovecot'
echo "   ✅ Services mail configurés (7 ports)"

echo ""
echo "📍 Étape 9/18 : FTP (ProFTPD)..."
ufw allow 21/tcp comment 'FTP control - ProFTPD'
ufw allow 49152:65534/tcp comment 'FTP passive mode - ProFTPD'
echo "   ✅ FTP configuré (port 21 + passive)"

echo ""
echo "📍 Étape 10/18 : OpenVPN..."
ufw allow 1194/udp comment 'OpenVPN server'
echo "   ✅ OpenVPN port 1194/udp ouvert"

echo ""
echo "📍 Étape 11/18 : Jitsi Meet - Services publics uniquement..."
ufw allow 10000/udp comment 'Jitsi JVB - Video bridge'
ufw allow 5222/tcp comment 'Prosody XMPP C2S'
ufw allow 5280/tcp comment 'Prosody BOSH HTTP'
ufw allow 5281/tcp comment 'Prosody BOSH HTTPS'
echo "   ✅ Jitsi services publics configurés"

echo ""
echo "📍 Étape 12/18 : Meilisearch (moteur de recherche)..."
ufw allow 7700/tcp comment 'Meilisearch API'
echo "   ✅ Meilisearch port 7700 ouvert"

echo ""
echo "📍 Étape 13/18 : Applications Docker PUBLIQUES..."
ufw allow 3000/tcp comment 'Docker Caddy reverse proxy - PUBLIC'
ufw allow 8000/tcp comment 'Docker Python/FastAPI app - PUBLIC'
ufw allow 8090/tcp comment 'Docker Python/Uvicorn app - PUBLIC'
echo "   ✅ 3 applications Docker exposées publiquement"

echo ""
echo "📍 Étape 14/18 : BLOCAGE des bases de données..."
ufw deny 3306/tcp comment 'BLOCK MariaDB - Use localhost only'
ufw deny 5432/tcp comment 'BLOCK PostgreSQL - Use localhost only'
ufw deny 6379/tcp comment 'BLOCK Redis - Use localhost only'
echo "   ✅ Bases de données bloquées (MariaDB, PostgreSQL, Redis)"

echo ""
echo "📍 Étape 15/18 : BLOCAGE TURN/STUN (Jitsi - débloquer si besoin)..."
ufw deny 3478 comment 'BLOCK STUN - Unblock if Jitsi issues'
ufw deny 3479 comment 'BLOCK STUN alt - Unblock if Jitsi issues'
ufw deny 5269 comment 'BLOCK Prosody XMPP S2S - Internal only'
ufw deny 5349 comment 'BLOCK TURN TCP - Unblock if Jitsi issues'
ufw deny 5350 comment 'BLOCK TURN - Unblock if Jitsi issues'
echo "   ✅ TURN/STUN bloqués (commentaires ajoutés pour déblocage)"

echo ""
echo "📍 Étape 16/18 : BLOCAGE services d'administration (VPN/IPs uniquement)..."
ufw deny 8889/tcp comment 'BLOCK JupyterLab - Access via VPN or IPs only'
ufw deny 10001/tcp comment 'BLOCK Webmin - Access via VPN or IPs only'
ufw deny 61208/tcp comment 'BLOCK Glances - Access via VPN or IPs only'
ufw deny 61209/tcp comment 'BLOCK Glances web - Access via VPN or IPs only'
ufw deny 20/tcp comment 'BLOCK FTP data port - Not needed with passive'
echo "   ✅ Services admin bloqués en public (accessibles via VPN/IPs)"

echo ""
echo "📍 Étape 17/18 : BLOCAGE Memcached (sécurité)..."
ufw deny 11211/tcp comment 'BLOCK Memcached - localhost only'
echo "   ✅ Memcached bloqué"

echo ""
echo "📍 Étape 18/18 : Activation UFW avec logging..."
ufw logging on
ufw --force enable
echo "   ✅ UFW activé avec logging"

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ CONFIGURATION TERMINÉE AVEC SUCCÈS !"
echo "════════════════════════════════════════════════════════"
echo ""
echo "📊 RÉSUMÉ DE LA CONFIGURATION :"
echo ""
echo "🔓 ACCÈS COMPLET (tout autorisé) :"
echo "   • Interface localhost (lo)"
echo "   • Interface VPN (tun0) - OpenVPN"
echo "   • IP: 154.120.176.213"
echo "   • IP: 157.173.104.204"
echo ""
echo "🌍 SERVICES PUBLICS (ouverts à tous) :"
echo "   • Web: 80, 443"
echo "   • Mail: 25, 587, 465, 110, 143, 993, 995"
echo "   • FTP: 21 + 49152-65534"
echo "   • OpenVPN: 1194/udp"
echo "   • Jitsi: 10000/udp, 5222, 5280, 5281"
echo "   • Meilisearch: 7700"
echo "   • Docker Apps: 3000, 8000, 8090"
echo ""
echo "🔒 SERVICES BLOQUÉS (VPN/IPs garde-fous uniquement) :"
echo "   • SSH: 49521"
echo "   • Webmin: 10001"
echo "   • JupyterLab: 8889"
echo "   • Glances: 61208, 61209"
echo "   • Bases de données: 3306, 5432, 6379"
echo "   • TURN/STUN: 3478, 3479, 5269, 5349, 5350"
echo "   • Memcached: 11211"
echo ""
echo "📋 Statut détaillé UFW :"
echo "════════════════════════════════════════════════════════"
ufw status verbose

echo ""
echo "🔍 VÉRIFICATIONS RECOMMANDÉES :"
echo "════════════════════════════════════════════════════════"
echo ""
echo "1. Test SSH via VPN :"
echo "   → Connectez-vous au VPN puis: ssh -p 49521 user@10.8.0.1"
echo ""
echo "2. Test SSH via IP garde-fou :"
echo "   → Depuis 154.120.176.213: ssh -p 49521 user@$IP_SERVEUR"
echo ""
echo "3. Test Webmin via VPN :"
echo "   → https://10.8.0.1:10001"
echo ""
echo "4. Test sites web publics :"
echo "   → http://votre-domaine.com"
echo "   → https://votre-domaine.com"
echo ""
echo "5. Test Docker apps :"
echo "   → http://votre-domaine.com:3000"
echo "   → http://votre-domaine.com:8000"
echo "   → http://votre-domaine.com:8090"
echo ""
echo "6. Vérifier les logs UFW :"
echo "   → tail -f /var/log/ufw.log"
echo ""
echo "💡 COMMANDES UTILES :"
echo "════════════════════════════════════════════════════════"
echo "• Voir toutes les règles numérotées : ufw status numbered"
echo "• Supprimer une règle : ufw delete [numéro]"
echo "• Débloquer TURN/STUN si Jitsi bug : ufw delete [numéro_règle]"
echo "• Recharger UFW : ufw reload"
echo "• Voir logs en temps réel : tail -f /var/log/ufw.log"
echo ""
echo "⚠️  IMPORTANT : Testez SSH via VPN AVANT de vous déconnecter !"
echo ""
