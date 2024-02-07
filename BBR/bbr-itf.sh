#!/bin/bash
echo "Скрипт для оптимизации TCP (+BBR) и UDP на Linux сервере от IT Freedom Project (https://www.youtube.com/@it-freedom-project), (https://github.com/IT-Freedom-Project/Youtube) "
# Функция для безопасного добавления настроек в файл, если они еще не существуют
add_if_not_exists() {
    local file="$1"
    local setting="$2"
    grep -qF -- "$setting" "$file" || echo "$setting" | sudo tee -a "$file"
}

echo "Обновление /etc/security/limits.conf..."
add_if_not_exists /etc/security/limits.conf "* soft nofile 51200"
add_if_not_exists /etc/security/limits.conf "* hard nofile 51200"
add_if_not_exists /etc/security/limits.conf "root soft nofile 51200"
add_if_not_exists /etc/security/limits.conf "root hard nofile 51200"

echo "Установка лимита открытых файлов..."
ulimit -n 51200

echo "Добавление настроек TCP и UDP в /etc/sysctl.conf..."
settings=(
    "fs.file-max = 51200"
    "net.core.rmem_max = 67108864"
    "net.core.wmem_max = 67108864"
    "net.core.netdev_max_backlog = 10000"
    "net.core.somaxconn = 4096"
    "net.core.default_qdisc = fq"
    "net.ipv4.tcp_syncookies = 1"
    "net.ipv4.tcp_tw_reuse = 1"
    "net.ipv4.tcp_fin_timeout = 30"
    "net.ipv4.tcp_keepalive_time = 1200"
    "net.ipv4.tcp_keepalive_probes = 5"
    "net.ipv4.tcp_keepalive_intvl = 30"
    "net.ipv4.tcp_max_syn_backlog = 8192"
    "net.ipv4.ip_local_port_range = 10000 65000"
    "net.ipv4.tcp_slow_start_after_idle = 0"
    "net.ipv4.tcp_max_tw_buckets = 5000"
    "net.ipv4.tcp_fastopen = 3"
    "net.ipv4.udp_mem = 25600 51200 102400"
    "net.ipv4.tcp_mem = 25600 51200 102400"
    "net.ipv4.tcp_rmem = 4096 87380 67108864"
    "net.ipv4.tcp_wmem = 4096 65536 67108864"
    "net.ipv4.tcp_mtu_probing = 1"
    "net.ipv4.tcp_congestion_control = bbr"
)

for setting in "${settings[@]}"; do
    add_if_not_exists /etc/sysctl.conf "$setting"
done

echo "Применение изменений..."
sudo sysctl -p

echo "Изменения успешно применены. Сервер будет перезагружен через 5 секунд..."
sleep 5
sudo reboot
