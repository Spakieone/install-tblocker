#!/bin/bash

# install_tblocker.sh
# Автоматическая установка Tblocker и настройка Remnanode
# Обновлённая версия: исправлена обработка ошибок dpkg и установка Tblocker
# Автор: ChatGPT
# Дата: 2025-08-30

# ===== Проверка root =====
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите скрипт от root (sudo)."
    exit 1
fi

echo "✅ Запускаем установку Tblocker..."

# ===== Исправление прерванного dpkg =====
if sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; then
    echo "❌ dpkg занят, завершите другие установки и попробуйте снова."
    exit 1
fi

if [ -f /var/lib/dpkg/lock ]; then
    echo "⚠ Предыдущая установка прервана. Исправляем dpkg..."
    sudo dpkg --configure -a
fi

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

# Удаляем ненужный том /var/lib/toblock
if grep -q "/var/lib/toblock:/var/lib/toblock" "$COMPOSE_FILE"; then
    echo "➡ Удаляем лишний том /var/lib/toblock из docker-compose.yml..."
    sed -i '/\/var\/lib\/toblock:\/var\/lib\/toblock/d' "$COMPOSE_FILE"
fi

# Добавляем только необходимый том /var/log/remnanode
if ! grep -q "/var/log/remnanode:/var/log/remnanode" "$COMPOSE_FILE"; then
    echo "➡ Добавляем том /var/log/remnanode в docker-compose.yml..."
    sed -i '/volumes:/a\            - '\''/var/log/remnanode:/var/log/remnanode'\''' "$COMPOSE_FILE"
else
    echo "✅ volumes для логов уже настроен."
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

# Проверяем, установился ли Tblocker
if [ ! -d /opt/tblocker ]; then
    echo "❌ Установка Tblocker не удалась. Проверьте вывод установки."
    exit 1
fi

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
systemctl daemon-reload
systemctl enable tblocker
systemctl restart tblocker

echo "✅ Установка завершена!"
systemctl status tblocker --no-pager
