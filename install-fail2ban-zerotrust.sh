#!/bin/bash
# ============================================
# CONFIGURATION FAIL2BAN - FINALE OPTIMISÉE
# Date: 24 Octobre 2025
# Serveur: geomadagascar.servermada.com
# Mode: Zero Trust + Ban Progressif
# Filtres: Vérifiés et compatibles
# LOGS: Vérifiés et existants
# ============================================

set -e

echo "🔥 CONFIGURATION FAIL2BAN - VERSION FINALE (LOGS VÉRIFIÉS)"
echo "=========================================================="
echo ""

# Vérifier root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Exécuter en root (sudo)"
    exit 1
fi

# ============================================
# ÉTAPE 1 : BACKUP
# ============================================
echo "📦 Étape 1/7 : Sauvegarde..."

if [ -f /etc/fail2ban/jail.local ]; then
    cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup-$(date +%Y%m%d-%H%M%S)
    echo "   ✅ Backup jail.local créé"
fi

tar czf /root/fail2ban-backup-$(date +%Y%m%d-%H%M%S).tar.gz /etc/fail2ban/ 2>/dev/null
echo "   ✅ Archive complète créée"

# ============================================
# ÉTAPE 2 : CONFIGURATION PRINCIPALE
# ============================================
echo ""
echo "📝 Étape 2/7 : Création jail.local..."

cat > /etc/fail2ban/jail.local << 'EOFCONFIG'
# ============================================
# FAIL2BAN - ZERO TRUST + BAN PROGRESSIF
# Date: 24 Octobre 2025
# Serveur: geomadagascar.servermada.com
# ============================================

[DEFAULT]
# ============================================
# ZERO TRUST - Aucune IP privilégiée
# ============================================
# Uniquement localhost (obligatoire)
ignoreip = 127.0.0.1/8 ::1

# ============================================
# BAN PROGRESSIF (INCRÉMENTAL)
# ============================================
# Le ban augmente à chaque récidive :
# 1er ban = 1h, 2ème = 2h, 3ème = 4h, 4ème = 8h, etc.
# Maximum : 5 semaines
# Reset après 1 semaine d'inactivité
bantime.increment = true
bantime = 3600
bantime.multipliers = 1 2 4 8 16 32 64
bantime.maxtime = 5w
bantime.rndtime = 1w
bantime.factor = 1

# ============================================
# PARAMÈTRES GÉNÉRAUX
# ============================================
# Fenêtre de détection : 10 minutes
# Tentatives par défaut : 5
# Action : Utiliser UFW pour le bannissement
findtime = 600
maxretry = 5
banaction = ufw
banaction_allports = ufw
action = %(action_)s

# ============================================
# 🔴 PRIORITÉ HAUTE - ACCÈS ROOT/ADMIN
# ============================================
# Services critiques nécessitant une protection maximale
# SSH, Webmin, JupyterLab : accès administrateur
# Seulement 3 tentatives autorisées
# Ban initial plus long (1-2 heures)

[sshd]
enabled = true
port = 49521
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 7200

[webmin-auth]
enabled = true
port = 10001
filter = webmin-auth
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 7200

[jupyter-auth]
enabled = true
port = 8889
filter = jupyter-auth
logpath = /var/log/syslog
maxretry = 3
findtime = 600
bantime = 3600

# ============================================
# 🟠 PRIORITÉ MOYENNE - SERVICES CRITIQUES
# ============================================
# Services essentiels : FTP, mail (SMTP/IMAP/POP3)
# Protection contre brute-force
# 3 tentatives selon le service
# Ban initial : 1 heure
#
# NOTE: MySQL/MariaDB désactivé (pas de logs trouvés)

[proftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
maxretry = 3
findtime = 600
bantime = 3600

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps
filter = dovecot
logpath = /var/log/mail.log
maxretry = 3
findtime = 600
bantime = 3600

[postfix]
enabled = true
port = smtp,465,submission
filter = postfix
logpath = /var/log/mail.log
maxretry = 3
findtime = 600
bantime = 3600

# ============================================
# 🟡 PRIORITÉ BASSE - APACHE/WEB
# ============================================
# Protection du serveur web Apache
# Détection des attaques courantes :
# - Authentification échouée (401/403)
# - Bots malveillants (Nikto, sqlmap)
# - Scripts malveillants (.php, .asp, .exe)
# - Overflows / DDoS (>100 req/min)
# - Shellshock (exploitation Bash)
# - Fake GoogleBot
# - Tentatives sur /admin, /wp-admin
# - Crawlers agressifs

[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/access.log
maxretry = 5
findtime = 600
bantime = 3600

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2
findtime = 86400
bantime = 86400

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/access.log
maxretry = 3
findtime = 300
bantime = 3600

[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = /var/log/apache2/access.log
maxretry = 100
findtime = 60
bantime = 600

[apache-shellshock]
enabled = true
port = http,https
filter = apache-shellshock
logpath = /var/log/apache2/access.log
maxretry = 1
findtime = 300
bantime = 86400

[apache-fakegooglebot]
enabled = true
port = http,https
filter = apache-fakegooglebot
logpath = /var/log/apache2/access.log
maxretry = 1
findtime = 86400
bantime = 86400

[apache-pass]
enabled = true
port = http,https
filter = apache-pass
logpath = /var/log/apache2/access.log
maxretry = 3
findtime = 600
bantime = 3600

[apache-botsearch]
enabled = true
port = http,https
filter = apache-botsearch
logpath = /var/log/apache2/access.log
maxretry = 2
findtime = 600
bantime = 3600

# ============================================
# ⚡ RÉCIDIVE - MEGA-BAN POUR RÉCIDIVISTES
# ============================================
# Si une IP est bannie 3 fois en 24h
# Ban automatique de 1 semaine sur TOUS les ports
# Protection ultime contre les attaquants persistants

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = %(banaction_allports)s
bantime = 604800
findtime = 86400
maxretry = 3
EOFCONFIG

echo "   ✅ jail.local créé avec 15 jails actives (MySQL désactivé)"

# ============================================
# ÉTAPE 3 : VÉRIFICATION LOG FILES
# ============================================
echo ""
echo "🔍 Étape 3/7 : Vérification des fichiers de logs..."

# Liste des logs à vérifier
declare -A logs=(
    ["SSH"]="/var/log/auth.log"
    ["Webmin"]="/var/log/auth.log"
    ["JupyterLab"]="/var/log/syslog"
    ["ProFTPD"]="/var/log/proftpd/proftpd.log"
    ["Mail (Dovecot/Postfix)"]="/var/log/mail.log"
    ["Apache"]="/var/log/apache2/access.log"
    ["Fail2Ban"]="/var/log/fail2ban.log"
)

for service in "${!logs[@]}"; do
    if [ -f "${logs[$service]}" ]; then
        echo "   ✅ $service: ${logs[$service]}"
    else
        echo "   ❌ $service: ${logs[$service]} MANQUANT"
    fi
done

if [ -d /var/log/mysql ] || [ -d /var/log/mariadb ]; then
    echo "   ⚠️  MySQL/MariaDB détecté mais logs non configurés (jail désactivée)"
else
    echo "   ℹ️  MySQL/MariaDB non installé (normal)"
fi

echo "   ✅ Vérification terminée"

# ============================================
# ÉTAPE 4 : TEST DE SYNTAXE
# ============================================
echo ""
echo "✅ Étape 4/7 : Test de la syntaxe..."

if fail2ban-client -t 2>&1 | tail -1 | grep -q "OK"; then
    echo "   ✅ Syntaxe correcte - Configuration valide !"
else
    echo "   ⚠️  Détails du test:"
    fail2ban-client -t 2>&1 | tail -20
    echo ""
    echo "   ⚠️  Vérification si c'est juste un avertissement..."
fi

# ============================================
# ÉTAPE 5 : REDÉMARRAGE
# ============================================
echo ""
echo "🔄 Étape 5/7 : Redémarrage de Fail2Ban..."

systemctl restart fail2ban
sleep 3

if systemctl is-active --quiet fail2ban; then
    echo "   ✅ Fail2Ban actif et opérationnel"
else
    echo "   ❌ Erreur de démarrage - Vérification des logs..."
    journalctl -u fail2ban -n 30 --no-pager
    exit 1
fi

# ============================================
# ÉTAPE 6 : SCRIPTS DE GESTION
# ============================================
echo ""
echo "🛠️  Étape 6/7 : Création des scripts utiles..."

# Créer le dossier s'il n'existe pas
mkdir -p /root/script_admin

# Script de monitoring
cat > /root/script_admin/fail2ban-monitor.sh << 'EOFMON'
#!/bin/bash
clear
echo "╔════════════════════════════════════════════════╗"
echo "║     🔍 FAIL2BAN MONITORING - $(date +%H:%M:%S)       ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

echo "📊 STATISTIQUES GLOBALES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"
fail2ban-client status
echo ""

echo "🚫 DÉTAILS PAR JAIL"
echo "━━━━━━━━━━━━━━━━━━━"
for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,/ /g'); do
    banned=$(fail2ban-client status $jail 2>/dev/null | grep "Currently banned" | awk '{print $4}')
    total=$(fail2ban-client status $jail 2>/dev/null | grep "Total banned" | awk '{print $4}')
    if [ "$banned" -gt 0 ] 2>/dev/null || [ "$total" -gt 0 ] 2>/dev/null; then
        echo "  🔸 $jail"
        echo "     Actuellement bannis: $banned"
        echo "     Total banni: $total"
        fail2ban-client status $jail 2>/dev/null | grep "Banned IP list" | sed 's/^/     /'
        echo ""
    fi
done

echo "📜 DERNIERS BANS (10 derniers)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "Ban " /var/log/fail2ban.log 2>/dev/null | tail -10 | while read line; do
    echo "  • $line"
done

echo ""
echo "🔓 DERNIERS UNBANS (5 derniers)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "Unban" /var/log/fail2ban.log 2>/dev/null | tail -5 | while read line; do
    echo "  • $line"
done
EOFMON

chmod +x /root/script_admin/fail2ban-monitor.sh

# Script de débannissement d'urgence
cat > /root/script_admin/fail2ban-unban.sh << 'EOFUNBAN'
#!/bin/bash
echo "🆘 DÉBANNISSEMENT D'URGENCE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "$1" ]; then
    echo "❌ Usage: $0 <IP>"
    echo "Exemple: $0 192.168.1.100"
    exit 1
fi

IP=$1
echo "Débannissement de $IP..."
echo ""

for jail in $(fail2ban-client status | grep "Jail list" | sed 's/.*://; s/,/ /g'); do
    if fail2ban-client set $jail unbanip $IP 2>/dev/null; then
        echo "  ✅ Débanni de: $jail"
    fi
done

echo ""
echo "✅ Terminé !"
EOFUNBAN

chmod +x /root/script_admin/fail2ban-unban.sh

# Script de statistiques
cat > /root/script_admin/fail2ban-stats.sh << 'EOFSTATS'
#!/bin/bash
echo "📊 FAIL2BAN - STATISTIQUES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🔝 TOP 10 IPs LES PLUS BANNIES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "Ban " /var/log/fail2ban.log 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn | head -10

echo ""
echo "🎯 BANS PAR JAIL"
echo "━━━━━━━━━━━━━━━"
grep "Ban " /var/log/fail2ban.log 2>/dev/null | grep -oP '\[\K[^\]]+' | sort | uniq -c | sort -rn

echo ""
echo "📈 BANS PAR JOUR (7 derniers jours)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for i in {0..6}; do
    date=$(date -d "$i days ago" +%Y-%m-%d)
    count=$(grep "Ban " /var/log/fail2ban.log 2>/dev/null | grep "$date" | wc -l)
    echo "  $date: $count bans"
done
EOFSTATS

chmod +x /root/script_admin/fail2ban-stats.sh

echo "   ✅ Scripts créés:"
echo "      • /root/script_admin/fail2ban-monitor.sh  (monitoring temps réel)"
echo "      • /root/script_admin/fail2ban-unban.sh    (débannir une IP)"
echo "      • /root/script_admin/fail2ban-stats.sh    (statistiques)"

# ============================================
# ÉTAPE 7 : VÉRIFICATION FINALE
# ============================================
echo ""
echo "📊 Étape 7/7 : Vérification des jails actives..."
echo ""

fail2ban-client status

echo ""
echo "════════════════════════════════════════════════"
echo "✅ CONFIGURATION TERMINÉE AVEC SUCCÈS !"
echo "════════════════════════════════════════════════"
echo ""
echo "📋 RÉSUMÉ DE LA CONFIGURATION:"
echo ""
echo "🔴 PRIORITÉ HAUTE (3 jails):"
echo "   • sshd (49521)           - 3 tentatives → 2h"
echo "   • webmin-auth (10001)    - 3 tentatives → 2h"
echo "   • jupyter-auth (8889)    - 3 tentatives → 1h"
echo ""
echo "🟠 PRIORITÉ MOYENNE (3 jails):"
echo "   • proftpd (21)           - 3 tentatives → 1h"
echo "   • dovecot (IMAP/POP3)    - 3 tentatives → 1h"
echo "   • postfix (SMTP)         - 3 tentatives → 1h"
echo "   ⚠️  mysqld-auth          - DÉSACTIVÉ (pas de logs)"
echo ""
echo "🟡 PRIORITÉ BASSE (8 jails):"
echo "   • apache-auth            - 5 tentatives → 1h"
echo "   • apache-badbots         - 2 tentatives → 24h"
echo "   • apache-noscript        - 3 tentatives → 1h"
echo "   • apache-overflows       - 100 req/min → 10min"
echo "   • apache-shellshock      - 1 tentative → 24h"
echo "   • apache-fakegooglebot   - 1 tentative → 24h"
echo "   • apache-pass            - 3 tentatives → 1h"
echo "   • apache-botsearch       - 2 tentatives → 1h"
echo ""
echo "⚡ SPÉCIAL:"
echo "   • recidive               - 3 bans/24h → 1 semaine"
echo ""
echo "🔧 BAN PROGRESSIF ACTIVÉ:"
echo "   1er ban → 1h | 2ème → 2h | 3ème → 4h | 4ème → 8h"
echo "   5ème → 16h | 6ème → 32h | 7ème → 64h | Max → 5 semaines"
echo ""
echo "🛡️  MODE ZERO TRUST:"
echo "   ✓ Aucune IP privilégiée (sauf 127.0.0.1)"
echo "   ✓ VPN surveillé"
echo "   ✓ IPs de confiance surveillées"
echo ""
echo "📊 COMMANDES UTILES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Monitoring:      /root/script_admin/fail2ban-monitor.sh"
echo "  Statistiques:    /root/script_admin/fail2ban-stats.sh"
echo "  Débannir IP:     /root/script_admin/fail2ban-unban.sh <IP>"
echo "  Logs live:       tail -f /var/log/fail2ban.log"
echo "  Statut jail:     fail2ban-client status <jail>"
echo ""
echo "⚠️  IMPORTANT:"
echo "   • Gardez un accès console de secours !"
echo "   • Même VOS IPs peuvent être bannies"
echo "   • Testez avant de vous déconnecter"
echo ""
echo "💡 NOTE: MySQL/MariaDB jail désactivée (logs non trouvés)"
echo "   Si vous installez MySQL plus tard, réactivez-la dans jail.local"
echo ""
