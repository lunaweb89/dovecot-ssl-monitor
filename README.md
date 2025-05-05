# 🔒 Dovecot SSL Expiry Monitor

This script monitors SSL certificates used by Dovecot (IMAP/POP) on `mail.<domain>` subdomains hosted under `/home/<domain>`. It sends email alerts if any cert is expired or expiring soon (≤ 15 days), and prints expiry status in the terminal.

## ✅ Features

- Detects and checks cert for `mail.<domain>` over port 993 (IMAPS)
- Displays expiry status in terminal output
- Sends email alerts using internal `sendmail` or `mailutils`
- Works with CyberPanel and other Linux-based hosting setups
- Cronjob runs daily at 7 AM by default

## 📦 Requirements

- Linux (Debian/Ubuntu/CentOS)
- `openssl`, `mailutils` or `mailx`
- Outbound mail capability (Postfix/sendmail must be functional)

## 🚀 Installation

On any new server, run:

```bash
curl -sL https://raw.githubusercontent.com/YOUR_USERNAME/dovecot-ssl-monitor/main/install-ssl-monitor.sh | bash
```

Replace `YOUR_USERNAME` with your actual GitHub username.

## 🛠 Configuration

Edit the script after installation:

```bash
sudo nano /usr/local/bin/check-dovecot-ssl.sh
```

Update this line with your preferred alert email:

```bash
EMAIL_TO="alerts@yourdomain.com"
```

## 📅 Cron Setup

The installer adds this to your crontab:

```
0 7 * * * /usr/local/bin/check-dovecot-ssl.sh
```

You can run the check manually anytime:

```bash
sudo /usr/local/bin/check-dovecot-ssl.sh
```

## 📨 Troubleshooting

- Make sure your server can send outbound mail (port 25 or via relay)
- Use `tail -f /var/log/mail.log` (or `/var/log/maillog`) to check delivery status
- Test manually:
  ```bash
  echo -e "Subject: Test\n\nBody" | sendmail -v alerts@yourdomain.com
  ```

## 📜 License

MIT License
