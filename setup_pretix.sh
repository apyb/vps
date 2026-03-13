
#!/bin/bash

# Exit immediately if a command fails
set -e

echo "1/7: Creating Pretix directories and assigning correct Docker UID (15371)..."
mkdir -p /var/pretix-data
chown -R 15371:15371 /var/pretix-data

mkdir -p /etc/pretix
touch /etc/pretix/pretix.cfg
chown -R 15371:15371 /etc/pretix/
chmod 0700 /etc/pretix/pretix.cfg

echo "2/7: Applying Redis configurations..."
# Append socket settings to redis.conf (only if they aren't already there to prevent duplicates on rerun)
grep -qF "unixsocket /var/run/redis/redis.sock" /etc/redis/redis.conf || echo "unixsocket /var/run/redis/redis.sock" >> /etc/redis/redis.conf
grep -qF "unixsocketperm 777" /etc/redis/redis.conf || echo "unixsocketperm 777" >> /etc/redis/redis.conf

# Automating 'systemctl edit redis-server' by creating the override file directly
mkdir -p /etc/systemd/system/redis-server.service.d
cat <<EOF > /etc/systemd/system/redis-server.service.d/override.conf
[Service]
# Keep the directory around so that pretix.service in docker does not need to be
# restarted when redis is restarted.
RuntimeDirectoryPreserve=yes
EOF

echo "3/7: Reloading systemd and restarting Redis..."
systemctl daemon-reload
systemctl restart redis-server

echo "4/7: Setting up the Pretix cronjob..."
# Creating a dedicated cron file in /etc/cron.d/ is cleaner than modifying the root crontab
cat <<EOF > /etc/cron.d/pretix
15,45 * * * * root /usr/bin/docker exec pretix.service pretix cron
EOF
chmod 0644 /etc/cron.d/pretix

echo "5/7: Pulling the stable Pretix standalone Docker image..."
docker pull pretix/standalone:stable

echo "6/7: Building the custom APyB Pretix image..."
if [ -f "/etc/pretix/Dockerfile" ]; then
    cd /etc/pretix
    docker build -t pretix-apyb:latest .
    # Return to previous directory
    cd - > /dev/null
else
    echo "------------------------------------------------------------------"
    echo "WARNING: /etc/pretix/Dockerfile not found! Skipping the custom build."
    echo "Please place your Dockerfile in /etc/pretix and manually run:"
    echo "cd /etc/pretix && docker build -t pretix-apyb:latest ."
    echo "------------------------------------------------------------------"
fi

echo "=================================================================="
echo "7/7: Pretix baseline environment setup complete!"
echo "=================================================================="
