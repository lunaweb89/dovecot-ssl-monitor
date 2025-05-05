#!/bin/bash

# === Install SSL Monitor Script for CyberPanel + Dovecot ===
# - Creates /usr/local/bin/check-dovecot-ssl.sh
# - Sets daily cron job
# - Uses internal mail (sendmail/mailx)
# - No system updates to prevent crash

set -e

EMAIL="alerts@yourdomain.com"  # <-- Replace with your email

MONITOR_SCRIPT="/usr/local/bin/check-dovecot-ssl.sh"

echo "[+] Installing dependencies..."
if command -v apt &>/dev/null; then
  sudo apt install -y mailutils openssl
elif command -v yum &>/dev/null; then
  sudo yum install -y mailx openssl
else
  echo "❌ Unsupported OS. Exiting."
  exit 1
fi

echo "[+] Creating SSL monitor script..."
sudo tee "$MONITOR_SCRIPT" > /dev/null <<EOF
#!/bin/bash

ALERT_THRESHOLD=15
ALERTS=""
EMAIL_TO="$EMAIL"
EMAIL_SUBJECT="[ALERT] Dovecot SSL Expiry Report from \$(hostname)"
TMP_EMAIL="/tmp/dovecot_ssl_alerts.txt"

echo "---- [DOVECOT SSL CHECK] \$(date) ----"

for dir in /home/*; do
  [[ -d "\$dir" ]] || continue

  domain=\$(basename "\$dir")
  [[ "\$domain" != *.* ]] && continue

  mail_domain="mail.\$domain"
  echo "🔍 Checking \$mail_domain:993..."

  if ! getent hosts "\$mail_domain" > /dev/null || ! timeout 2 bash -c "</dev/tcp/\$mail_domain/993" 2>/dev/null; then
    echo "⚠️ Skipping \$mail_domain (DNS or port 993 issue)"
    echo "---------------------------------------------"
    continue
  fi

  cert_info=\$(echo | openssl s_client -connect "\$mail_domain:993" -servername "\$mail_domain" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate)
  if [[ -z "\$cert_info" ]]; then
    echo "❌ Unable to retrieve cert from \$mail_domain"
    echo "---------------------------------------------"
    continue
  fi

  expiry_raw=\$(echo "\$cert_info" | grep notAfter= | cut -d= -f2-)
  expiry_date=\$(date -d "\$expiry_raw" +"%Y-%m-%d")
  expiry_ts=\$(date -d "\$expiry_raw" +%s)
  now_ts=\$(date +%s)
  days_left=\$(( (expiry_ts - now_ts) / 86400 ))

  if (( expiry_ts < now_ts )); then
    status="❌ EXPIRED"
    ALERTS+="❌ EXPIRED: \$mail_domain (expired on \$expiry_date)\n"
  elif (( days_left <= ALERT_THRESHOLD )); then
    status="⚠️ Expiring Soon (\$days_left days left)"
    ALERTS+="⚠️ Expiring Soon: \$mail_domain (expires in \$days_left days on \$expiry_date)\n"
  else
    status="✅ Valid (\$days_left days left)"
  fi

  echo "Domain    : \$mail_domain"
  echo "Expires   : \$expiry_date"
  echo "Status    : \$status"
  echo "---------------------------------------------"
done

if [[ -n "\$ALERTS" ]]; then
  {
    echo "Subject: \$EMAIL_SUBJECT"
    echo "To: \$EMAIL_TO"
    echo "From: \$EMAIL_TO"
    echo ""
    echo -e "The following SSL certificates are expired or expiring soon:\n"
    echo -e "\$ALERTS"
  } > "\$TMP_EMAIL"

  /usr/sbin/sendmail -t < "\$TMP_EMAIL" || mail -s "\$EMAIL_SUBJECT" "\$EMAIL_TO" < "\$TMP_EMAIL"
  echo "🚨 Alert email sent to \$EMAIL_TO"
else
  echo "✅ No expiring or expired certs."
fi
EOF

echo "[+] Making script executable..."
sudo chmod +x "$MONITOR_SCRIPT"

echo "[+] Adding to crontab..."
(crontab -l 2>/dev/null; echo "0 7 * * * $MONITOR_SCRIPT") | sort -u | crontab -

echo "[+] Done. Run manually with:"
echo "    sudo $MONITOR_SCRIPT"
