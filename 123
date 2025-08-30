#!/bin/bash

# Установка Tblocker   
# Поддержка: @Spakieone

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Установка Tblocker Solobot (на базе скрипта Spakieone)${NC}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Скрипт должен запускаться от root. Используйте sudo.${NC}"
   exit 1
fi

# === Ввод данных от пользователя ===
read -p "🌐 Введите домен вашего бота (например https://t.me/yourbot  ): " BOT_DOMAIN
if [[ -z "$BOT_DOMAIN" ]]; then
    echo -e "${RED}Домен не может быть пустым!${NC}"
    exit 1
fi

read -p "⏱️ Введите время блокировки в минутах (по умолчанию 30): " BLOCK_DURATION
BLOCK_DURATION=${BLOCK_DURATION:-30}

# === Пути ===
NODE_DIR="/opt/remnanode"
LOG_DIR="/var/log/remnanode"
LOG_FILE="$LOG_DIR/access.log"
DOCKER_COMPOSE="$NODE_DIR/docker-compose.yml"
LOGROTATE_CONFIG="/etc/logrotate.d/remnanode"
TBLOCKER_CONFIG="/opt/tblocker/config.yaml"

# === 1. Настройка RemnaNode ===
echo -e "\n${YELLOW}🔧 1. Настройка RemnaNode (логи и volume)${NC}"

if [[ ! -d "$NODE_DIR" ]]; then
    echo -e "${RED}❌ Папка $NODE_DIR не найдена! Убедитесь, что нода Remna установлена.${NC}"
    exit 1
fi

cd "$NODE_DIR"

# Резервная копия
cp "$DOCKER_COMPOSE" "${DOCKER_COMPOSE}.backup.$(date +%s)" 2>/dev/null || true

# Добавляем volume, если его нет
if ! grep -q "/var/log/remnanode:/var/log/remnanode" "$DOCKER_COMPOSE"; then
    awk '
    /image: remnawave\/node:latest/ {
        print
        print "        volumes:"
        print "            - '\'''\/var\/log\/remnanode:\/var\/log\/remnanode'\'''"
    }
    !/image: remnawave\/node:latest/ { print }
    ' "$DOCKER_COMPOSE" > temp.yml && mv temp.yml "$DOCKER_COMPOSE"
    echo -e "${GREEN}✅ Volume для логов добавлен в docker-compose.yml${NC}"
else
    echo -e "${GREEN}✅ Volume для логов уже настроен${NC}"
fi
# Создаём папку логов
mkdir -p "$LOG_DIR"
# Установка logrotate (если нет)
if ! command -v logrotate &> /dev/null; then
    echo -e "${YELLOW}📦 Устанавливаем logrotate...${NC}"
    apt update -qq > /dev/null
    apt install -y logrotate > /dev/null
fi
# Конфиг logrotate
cat > "$LOGROTATE_CONFIG" << EOF
$LOG_DIR/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOF
echo -e "${GREEN}📝 Конфиг logrotate создан: $LOGROTATE_CONFIG${NC}"
# Применяем
logrotate -vf "$LOGROTATE_CONFIG"
# Перезапуск ноды
echo -e "${YELLOW}🔄 Перезапускаем RemnaNode...${NC}"
docker compose down > /dev/null 2>&1 || true
docker compose up -d
echo -e "${GREEN}✅ Нода перезапущена${NC}"
# === 2. Инструкция по Xray ===
echo -e "\n${YELLOW}📝 2. Настройка Xray (вручную)${NC}"
echo -e "${GREEN}Перейдите в панель RemnaWave → Профили → Конфиг Xray и внесите изменения:${NC}"
cat << 'EOF'
🔹 В "log" замените на:
  "log": {
    "error": "/var/log/remnanode/error.log",
    "access": "/var/log/remnanode/access.log",
    "loglevel": "warning"
  }
🔹 В "outbounds" добавьте:
{
  "tag": "TORRENT",
  "protocol": "blackhole"
}
🔹 В "routing" добавьте:
{
    "type": "field",
    "protocol": ["bittorrent"],
    "outboundTag": "TORRENT"
}
✅ Нажмите 'Форматировать' и 'Сохранить'
EOF
# === 3. Установка Tblocker через твой Gist ===
echo -e "\n${YELLOW}⬇️ 3. Устанавливаем Tblocker через ваш скрипт...${NC}"
# Удаляем старую версию
apt remove -y tblocker > /dev/null 2>&1 || true
# Скачиваем и запускаем твой скрипт с автоматическими ответами
echo -e "${GREEN}Запускаем скрипт из Gist: $BOT_DOMAIN${NC}"
# Автоматизируем ввод: путь к логу → 1 (iptables)
{
    echo "$LOG_FILE"
    echo "1"
} | bash <(curl -fsSL https://gist.githubusercontent.com/Spakieone/c5d63f98664b399fac36d5cdf68a65b5/raw/install-tblocker.sh  )
# === 4. Настройка config.yaml ===
echo -e "\n${YELLOW}⚙️ 4. Настраиваем config.yaml Tblocker${NC}"
if [[ ! -f "$TBLOCKER_CONFIG" ]]; then
    echo -e "${RED}❌ Файл конфигурации Tblocker не найден! Установка прервана.${NC}"
    exit 1
fi
# Резервная копия
cp "$TBLOCKER_CONFIG" "${TBLOCKER_CONFIG}.backup.$(date +%s)" 2>/dev/null || true
# Перезаписываем config.yaml
cat > "$TBLOCKER_CONFIG" << EOF
LogFile: "$LOG_FILE"
BlockDuration: $BLOCK_DURATION
TorrentTag: "TORRENT"
BlockMode: "iptables"
BypassIPS:
  - "127.0.0.1"
  - "::1"
StorageDir: "/opt/tblocker"
UsernameRegex: "email: (\\\\S+)"
SendWebhook: true
WebhookURL: "$BOT_DOMAIN/tblocker/webhook"
WebhookTemplate: '{"username":"%s","ip":"%s","server":"%s","action":"%s","duration":%d,"timestamp":"%s"}'
EOF
echo -e "${GREEN}✅ Конфиг Tblocker обновлён с вебхуком: $BOT_DOMAIN/tblocker/webhook${NC}"
# === 5. Перезапуск Tblocker ===
echo -e "${YELLOW}🔄 Перезапускаем Tblocker...${NC}"
systemctl stop tblocker || true
systemctl start tblocker
systemctl enable tblocker > /dev/null 2>&1 || true
# Проверка статуса
if systemctl is-active --quiet tblocker; then
    echo -e "${GREEN}✅ Tblocker успешно запущен!${NC}"
else
    echo -e "${RED}❌ Tblocker не запущен. Проверьте: systemctl status tblocker${NC}"
    exit 1
fi
# === Финал ===
echo -e "\n${GREEN}🎉 Установка Tblocker Solobot завершена!${NC}"
echo -e "📌 Время блокировки: ${BLOCK_DURATION} мин"
echo -e "🔗 Вебхук: $BOT_DOMAIN/tblocker/webhook"
echo -e "📄 Логи ноды: $LOG_FILE"
echo -e "🔍 Проверить Tblocker: journalctl -u tblocker -f"
echo -e "\n💡 Не забудьте настроить Xray в панели RemnaWave!"
