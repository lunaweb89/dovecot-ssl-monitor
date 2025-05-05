#!/bin/bash

# === Install SSL Monitor Script for CyberPanel + Dovecot ===
# - Creates /usr/local/bin/check-dovecot-ssl.sh
# - Sets daily cron job
# - Uses local mail for alerts
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
sudo tee "$MONITOR_SCRIPT" > /dev/null <<'EOF'
#!/bin/bash

ALERT_THRESHOLD=7
RENEWED_DOMAINS=""
EMAIL_TO="alerts@yourdomain.com"
EMAIL_SUBJECT="[INFO] SSL Renewals from $(hostname)"
TMP_EMAIL="/tmp/dovecot_ssl_renewals.txt"

echo "---- [SSL CERT CHECK] $(date) ----"

for dir in /home/*; do
  [[ -d "$dir" ]] || continue

  domain=$(basename "$dir")
  [[ "$domain" != *.* ]] && continue

  for check_domain in "$domain" "mail.$domain"; do
    echo "🔍 Checking $check_domain:443..."

    if ! getent hosts "$check_domain" > /dev/null || ! timeout 2 bash -c "</dev/tcp/$check_domain/443" 2>/dev/null; then
      echo "⚠️ Skipping $check_domain (DNS or port 443 issue)"
      echo "---------------------------------------------"
      continue
    fi

    cert_info=$(echo | openssl s_client -connect "$check_domain:443" -servername "$check_domain" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate)
    if [[ -z "$cert_info" ]]; then
      echo "❌ Unable to retrieve cert from $check_domain"
      echo "---------------------------------------------"
      continue
    fi

    expiry_raw=$(echo "$cert_info" | grep notAfter= | cut -d= -f2-)
    expiry_date=$(date -d "$expiry_raw" +"%Y-%m-%d")
    expiry_ts=$(date -d "$expiry_raw" +%s)
    now_ts=$(date +%s)
    days_left=$(( (expiry_ts - now_ts) / 86400 ))

    if (( expiry_ts < now_ts || days_left <= ALERT_THRESHOLD )); then
      echo "🔁 Attempting to renew cert for $domain..."
      if /usr/bin/cyberpanel issueSSL --domainName "$domain"; then
        RENEWED_DOMAINS+="✅ Renewed: $check_domain (was expiring on $expiry_date)\n"
      else
        RENEWED_DOMAINS+="❌ Renewal failed: $check_domain\n"
      fi
    fi

    echo "Domain    : $check_domain"
    echo "Expires   : $expiry_date"
    echo "Days Left : $days_left"
    echo "---------------------------------------------"
  done
done

if [[ -n "$RENEWED_DOMAINS" ]]; then
  {
    echo "Subject: $EMAIL_SUBJECT"
    echo "To: $EMAIL_TO"
    echo "From: $EMAIL_TO"
    echo ""
    echo -e "The following SSL certificates were renewed on $(date):\n"
    echo -e "$RENEWED_DOMAINS"
  } > "$TMP_EMAIL"

  /usr/sbin/sendmail -t < "$TMP_EMAIL" || mail -s "$EMAIL_SUBJECT" "$EMAIL_TO" < "$TMP_EMAIL"
  echo "📬 Renewal report sent to $EMAIL_TO"
else
  echo "✅ No renewals required today."
fi
EOF

echo "[+] Making script executable..."
sudo chmod +x "$MONITOR_SCRIPT"

echo "[+] Adding to crontab..."
(crontab -l 2>/dev/null; echo "0 7 * * * $MONITOR_SCRIPT") | sort -u | crontab -

echo "[+] Done. Run manually with:"
echo "    sudo $MONITOR_SCRIPT"
