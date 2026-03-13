#!/bin/bash

# Exit immediately if a command fails
set -e

# --- CONFIGURATION ---
DOMAIN="ingressos.python.org.br"
EMAIL="tecnologia@python.org.br"
REAL_CONF_FILE="/home/apyb/pretix"
# ---------------------

# Safety Check: Ensure your real config file actually exists
if [ ! -f "$REAL_CONF_FILE" ]; then
            echo "ERROR: The file $REAL_CONF_FILE was not found."
                echo "Please place your Nginx configuration file there before running this script."
                    exit 1
fi

echo "1/6: Removing default Nginx configuration..."
rm -f /etc/nginx/sites-enabled/default

echo "2/6: Creating temporary HTTP-only Nginx configuration to break the loop..."
cat <<EOF > /etc/nginx/sites-available/pretix
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/html;
}
EOF

echo "3/6: Linking the configuration and starting Nginx..."
ln -sf /etc/nginx/sites-available/pretix /etc/nginx/sites-enabled/
systemctl restart nginx

echo "4/6: Running Certbot to generate the certificates..."
# This runs non-interactively, agrees to TOS, and uses the Nginx plugin
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

echo "5/6: Certificates acquired! Copying your real Pretix configuration into place..."
cp "$REAL_CONF_FILE" /etc/nginx/sites-available/pretix

echo "6/6: Testing syntax and reloading Nginx with the secure configuration..."
nginx -t
systemctl reload nginx

echo "Enabling automatic Certbot renewal timer..."
systemctl enable --now certbot.timer
