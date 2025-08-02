#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# 0. Log all output for debugging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# 1. Install core packages
apt-get update
apt-get install -y \
  software-properties-common \
  curl \
  unzip \
  build-essential \
  jq \
  python3.11 \
  python3.11-venv \
  python3.11-dev \
  git \
  awscli \
  nginx

# 2. Securely fetch and install the SSH deploy key
# These variables are passed in from the launch template
: "$${deploy_key_secret_arn:?Need deploy_key_secret_arn}"
: "$${region:?Need region}"

aws secretsmanager get-secret-value \
  --secret-id "${deploy_key_secret_arn}" \
  --region "${region}" \
  --query SecretString --output text > /home/ubuntu/.ssh/id_rsa

chmod 600 /home/ubuntu/.ssh/id_rsa
chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa

# 3. Trust GitHub’s host key so SSH won't prompt
ssh-keyscan github.com >> /home/ubuntu/.ssh/known_hosts
chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts

# 4. Clone your private repo as the ubuntu user
sudo -u ubuntu git clone git@github.com:SecurityKane/magi.git /opt/magi

# 5. Set ownership
chown -R ubuntu:ubuntu /opt/magi

# 6. Create Python virtual environment and install dependencies
sudo -u ubuntu python3.11 -m venv /opt/magi/venv
/opt/magi/venv/bin/pip install --upgrade pip
/opt/magi/venv/bin/pip install -r /opt/magi/requirements.txt

# 7. Create systemd service for FastAPI app
cat <<EOF > /etc/systemd/system/magi.service
[Unit]
Description=Magi AI API
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/magi
EnvironmentFile=/etc/magi.env
ExecStart=/opt/magi/venv/bin/uvicorn app.main:app \\
  --host 127.0.0.1 --port 8000 --log-config log_config.yaml
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 8. Nginx reverse proxy (localhost only for testing)
cat <<EOF > /etc/nginx/sites-available/magi
server {
    listen 127.0.0.1:80;
    server_name localhost;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
ln -sf /etc/nginx/sites-available/magi /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 9. Startup wrapper: fetch secrets then start services
cat <<'EOF' > /opt/magi/start-app.sh
#!/bin/bash
set -e
: "$${db_secret_arn:?Need db_secret_arn}"
: "$${region:?Need region}"

SECRET_JSON=\$$(aws secretsmanager get-secret-value \
  --secret-id "\$${db_secret_arn}" \
  --region "\$${region}" \
  --query SecretString --output text)

echo "DATABASE_URL=\$(echo \$SECRET_JSON | jq -r .db_connection_string)" > /etc/magi.env
echo "SECRET_KEY=\$(echo \$SECRET_JSON | jq -r .app_secret_key)" >> /etc/magi.env

chown ubuntu:ubuntu /etc/magi.env
chmod 600 /etc/magi.env

systemctl start magi
systemctl reload nginx
EOF
chmod +x /opt/magi/start-app.sh

# 10. One-shot systemd unit to run start-app.sh
cat <<EOF > /etc/systemd/system/magi-startup.service
[Unit]
Description=Fetch secrets and start Magi AI API
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/magi/start-app.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 11. Enable and start everything
systemctl daemon-reload
systemctl enable magi-startup.service
systemctl enable magi.service
systemctl enable nginx
systemctl start magi-startup.service