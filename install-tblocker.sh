#!/bin/bash

# install_tblocker.sh
# Автоматическая установка Tblocker и настройка Remnanode
# GitHub-версия

# ===== Проверка root =====
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите скрипт от root (sudo)."
    exit 1
fi

echo "✅ Запускаем установку Tblocker..."

# ===== Удаление старого Tblocker =====
if dpkg -l | grep -q tblocker; then
    echo "➡ Найден старый Tblocker, удаляем..."
    apt remove -y tblocker
fi

# ===== Обновление и установка зависимостей =====
echo "➡ Обновляем пакеты и ставим зависимости..."
apt update -y
apt install -y curl logrotate docker docker-compose

# ===== Настройка docker-compose.yml =====
COMPOSE_FILE="/opt/remnanode/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Файл $COMPOSE_FILE не найден. Проверьте путь!"
    exit 1
fi

if ! grep -q "/var/log/remnanode" "$COMPOSE_FILE"; then
    echo "➡ Добавляем volumes в docker-compose.yml..."
    sed -i '/volumes:/a\            - '\''/var/log/remnanode:/var/log/remnanode'\''' "$COMPOSE_FILE"
else
    echo "✅ volumes уже настроен."
fi

# ===== Создание папки логов =====
mkdir -p /var/log/remnanode
chmod 755 /var/log/remnanode

# ===== Настройка logrotate =====
LOGROTATE_FILE="/etc/logrotate.d/remnanode"
if [ ! -f "$LOGROTATE_FILE" ]; then
    echo "➡ Создаём конфиг logrotate..."
    cat > "$LOGROTATE_FILE" <<EOL
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOL
else
    echo "✅ logrotate уже настроен."
fi

logrotate -vf "$LOGROTATE_FILE"

# ===== Перезапуск контейнеров =====
echo "➡ Перезапуск контейнеров Remnanode..."
cd /opt/remnanode || exit
docker compose down && docker compose up -d

# ===== Установка Tblocker =====
echo "➡ Устанавливаем Tblocker..."
bash <(curl -fsSL git.new/install) <<EOF
/var/log/remnanode/access.log
1
EOF

# ===== Ввод параметров =====
read -p "Введите домен бота (пример: vpn-bot.site): " BOT_DOMAIN
read -p "Введите время блокировки (в минутах): " BLOCK_DURATION

# ===== Создание конфига Tblocker =====
CONFIG_FILE="/opt/tblocker/config.yaml"
echo "➡ Создаём конфиг $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<EOL
LogFile: "/var/log/remnanode/access.log"
BlockDuration: $BLOCK_DURATION
TorrentTag: "TORRENT"
BlockMode: "iptables"
BypassIPS:
  - "127.0.0.1"
  - "::1"
StorageDir: "/opt/tblocker"
UsernameRegex: "email: (\\\\S+)"
SendWebhook: true
WebhookURL: "https://$BOT_DOMAIN/tblocker/webhook"
WebhookTemplate: '{"username":"%s","ip":"%s","server":"%s","action":"%s","duration":%d,"timestamp":"%s"}'
EOL

# ===== Перезапуск Tblocker =====
echo "➡ Перезапуск Tblocker..."
systemctl stop tblocker
systemctl start tblocker

echo "✅ Установка завершена!"
systemctl status tblocker --no-pager
