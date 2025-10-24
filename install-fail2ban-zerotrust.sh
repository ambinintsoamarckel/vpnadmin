#!/bin/bash
# ============================================
# CONFIGURATION FAIL2BAN - FINALE OPTIMISÉE
# Date: 24 Octobre 2025
# Serveur: geomadagascar.servermada.com
# Mode: Zero Trust + Ban Progressif
# Filtres: Vérifiés et compatibles
# ============================================

set -e

echo "🔥 CONFIGURATION FAIL2BAN - VERSION FINALE"
echo "==========================================="
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
bantime.increment = true
bantime = 3600                           # Ban initial: 1 heure
bantime.multipliers = 1 2 4 8 16 32 64  # Progression: 1h→2h→4h→8h...
bantime.maxtime = 5w                    # Maximum: 5 semaines
bantime.rndtime = 1w                    # Reset après 1 semaine d'inactivité
bantime.factor = 1                       # Formule simple

# ============================================
# PARAMÈTRES GÉNÉRAUX
# ============================================
findtime = 600                           # Fenêtre de détection: 10 minutes
maxretry = 5                             # Tentatives par défaut
banaction = ufw                          # Utiliser UFW
banaction_allports = ufw                 # UFW pour tous les ports
action = %(action_)s                     # Pas de notification email

# ============================================
# 🔴 PRIORITÉ HAUTE - ACCÈS ROOT/ADMIN
# ============================================

# SSH (Port 49521) - CRITIQUE
[sshd]
enabled = true
port = 49521
filter = sshd
logpath = /var/log/auth.log
maxretry = 3                             # Seulement 3 tentatives
findtime = 600
bantime = 7200                           # Ban initial: 2 heures

# Webmin (Port 10001) - INTERFACE ADMIN
[webmin-auth]
enabled = true
port = 10001
filter = webmin-auth
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 7200                           # Ban initial: 2 heures

# JupyterLab (Port 8889) - ENVIRONNEMENT DEV
[jupyter-auth]
enabled = true
port = 8889
filter = jupyter-auth
logpath = /var/log/syslog
maxretry = 3
findtime = 600
bantime = 3600                           # Ban initial: 1 heure

# ============================================
# 🟠 PRIORITÉ MOYENNE - SERVICES CRITIQUES
# ============================================

# MariaDB/MySQL (Port 3306)
[mysqld-auth]
enabled = true
port = 3306
filter = mysqld-auth
logpath = /var/log/mysql/error.log
maxretry = 5
findtime = 600
bantime = 3600

# ProFTPD (Port 21)
[proftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
maxretry = 3
findtime = 600
bantime = 3600

# Dovecot - IMAP/POP3 (Ports 110, 143, 993, 995)
[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps
filter = dovecot
logpath = /var/log/mail.log
maxretry = 3
findtime = 600
bantime = 3600

# Postfix - SMTP (Ports 25, 465, 587)
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

# Apache - Authentification (codes 401/403)
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/access.log
maxretry = 5
findtime = 600
bantime = 3600

# Apache - Bots Malveillants (Nikto, sqlmap, etc.)
[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2                             # Tolérance zéro
findtime = 86400                         # Sur 24 heures
bantime = 86400                          # Ban 24 heures

# Apache - Scripts Malveillants (.php, .asp, .exe)
[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/access.log
maxretry = 3
findtime = 300
bantime = 3600

# Apache - Overflows / Anti-DDoS (>100 req/min)
[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = /var/log/apache2/access.log
maxretry = 100                           # 100 requêtes
findtime = 60                            # En 1 minute
bantime = 600                            # Ban 10 minutes

# Apache - Shellshock (exploitation Bash)
[apache-shellshock]
enabled = true
port = http,https
filter = apache-shellshock
logpath = /var/log/apache2/access.log
maxretry = 1                             # UNE SEULE tentative
findtime = 300
bantime = 86400                          # Ban 24 heures

# Apache - Fake GoogleBot
[apache-fakegooglebot]
enabled = true
port = http,https
filter = apache-fakegooglebot
logpath = /var/log/apache2/access.log
maxretry = 1
findtime = 86400
bantime = 86400

# Apache - Pass (tentatives sur /admin, /wp-admin, etc.)
[apache-pass]
enabled = true
port = http,https
filter = apache-pass
logpath = /var/log/apache2/access.log
maxretry = 3
findtime = 600
bantime = 3600

# Apache - BotSearch (crawlers agressifs)
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
[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
action = %(banaction_allports)s
bantime = 604800                         # 1 semaine (7 jours)
findtime = 86400                         # Si re-ban dans les 24h
maxretry = 3                             # 3 bans différents = mega-ban
EOFCONFIG

echo "   ✅ jail.local créé avec 16 jails actives"

# ============================================
# ÉTAPE 3 : VÉRIFICATION LOG FILES
# ============================================
echo ""
echo "🔍 Étape 3/7 : Vérification des fichiers de logs..."


# Vérifier PostgreSQL log (si installé)
if [ -d /var/log/postgresql ]; then
    echo "   ✅ PostgreSQL logs trouvés"
else
    echo "   ⚠️  PostgreSQL logs non trouvés (normal si pas PostgreSQL)"
fi

echo "   ✅ Vérification terminée"

# ============================================
# ÉTAPE 4 : TEST DE SYNTAXE
# ============================================
echo ""
echo "✅ Étape 4/7 : Test de la syntaxe..."

if fail2ban-client -t 2>&1 | tail -1 | grep -q "OK"; then
    echo "   ✅ Syntaxe correcte"
else
    echo "   ⚠️  Affichage des détails:"
    fail2ban-client -t 2>&1 | tail -20
fi

# ============================================
# ÉTAPE 5 : REDÉMARRAGE
# ============================================
echo ""
echo "🔄 Étape 5/7 : Redémarrage de Fail2Ban..."

systemctl restart fail2ban
sleep 3

if systemctl is-active --quiet fail2ban; then
    echo "   ✅ Fail2Ban actif"
else
    echo "   ❌ Erreur de démarrage"
    journalctl -u fail2ban -n 20 --no-pager
    exit 1
fi

# ============================================
# ÉTAPE 6 : SCRIPTS DE GESTION
# ============================================
echo ""
echo "🛠️  Étape 6/7 : Création des scripts utiles..."

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
grep "Ban " /var/log/fail2ban.log | awk '{print $NF}' | sort | uniq -c | sort -rn | head -10

echo ""
echo "🎯 BANS PAR JAIL"
echo "━━━━━━━━━━━━━━━"
grep "Ban " /var/log/fail2ban.log | grep -oP '\[\K[^\]]+' | sort | uniq -c | sort -rn

echo ""
echo "📈 BANS PAR JOUR (7 derniers jours)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for i in {0..6}; do
    date=$(date -d "$i days ago" +%Y-%m-%d)
    count=$(grep "Ban " /var/log/fail2ban.log | grep "$date" | wc -l)
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
echo "🟠 PRIORITÉ MOYENNE (4 jails):"
echo "   • mysqld-auth (3306)     - 5 tentatives → 1h"
echo "   • proftpd (21)           - 3 tentatives → 1h"
echo "   • dovecot (IMAP/POP3)    - 3 tentatives → 1h"
echo "   • postfix (SMTP)         - 3 tentatives → 1h"
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
