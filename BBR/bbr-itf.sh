#!/bin/bash
echo "Скрипт для оптимизации TCP (+BBR) и UDP на Linux сервере от IT Freedom Project (https://www.youtube.com/@it-freedom-project), (https://github.com/IT-Freedom-Project/Youtube)"

# Функция для удаления существующих строк с параметрами в файле
remove_existing_settings() {
    local file="$1"
    sudo sed -i '/^\(\*\|root\) \(soft\|hard\) nofile/d' "$file"
    echo "Удалены существующие строки с параметрами в $file"
}

# Функция для добавления настроек в файл
add_settings() {
    local file="$1"
    local setting="$2"
    echo "$setting" | sudo tee -a "$file"
    echo "Добавлено: $setting в $file"
}

echo "Обновление /etc/security/limits.conf и /etc/sysctl.conf..."

# Удаляем существующие строки с параметрами в /etc/security/limits.conf
remove_existing_settings /etc/security/limits.conf

# Добавляем настройки в /etc/security/limits.conf
add_settings /etc/security/limits.conf "* soft nofile 51200" # Устанавливаем мягкий лимит на количество открытых файлов
add_settings /etc/security/limits.conf "* hard nofile 51200" # Устанавливаем жесткий лимит на количество открытых файлов
add_settings /etc/security/limits.conf "root soft nofile 51200" # Мягкий лимит для root
add_settings /etc/security/limits.conf "root hard nofile 51200" # Жесткий лимит для root

# Добавляем или обновляем настройки в /etc/sysctl.conf
settings=(
    "fs.file-max = 51200" # Максимальное количество открытых файлов для всей системы
    "net.core.rmem_max = 67108864" # Максимальный размер буфера приема для всех сокетов
    "net.core.wmem_max = 67108864" # Максимальный размер буфера отправки для всех сокетов
    "net.core.netdev_max_backlog = 10000" # Максимальное количество пакетов в очереди интерфейса перед обработкой
    "net.core.somaxconn = 4096" # Лимит размера очереди запросов на установление соединения
    "net.core.default_qdisc = fq" # Планировщик очереди по умолчанию, используемый для управления перегрузками
    "net.ipv4.tcp_syncookies = 1" # Включение SYN cookies для защиты от SYN flood атак
    "net.ipv4.tcp_tw_reuse = 1" # Позволяет повторно использовать TIME-WAIT сокеты для новых соединений
    "net.ipv4.tcp_fin_timeout = 30" # Таймаут для закрытия соединения на стороне, отправившей FIN
    "net.ipv4.tcp_keepalive_time = 1200" # Время в секундах до начала отправки keepalive пакетов
    "net.ipv4.tcp_keepalive_probes = 5" # Количество keepalive проб, прежде чем соединение будет считаться разорванным
    "net.ipv4.tcp_keepalive_intvl = 30" # Интервал между keepalive пробами
    "net.ipv4.tcp_max_syn_backlog = 8192" # Максимальное количество соединений в очереди на установление
    "net.ipv4.ip_local_port_range = 10000 65000" # Диапазон портов, используемых для исходящих соединений
    "net.ipv4.tcp_slow_start_after_idle = 0" # Отключает slow start после идлового состояния соединения
    "net.ipv4.tcp_max_tw_buckets = 5000" # Максимальное количество сокетов в состоянии TIME-WAIT
    "net.ipv4.tcp_fastopen = 3" # Включает TCP Fast Open на стороне клиента и сервера
    "net.ipv4.udp_mem = 25600 51200 102400" # Параметры памяти UDP: мин., давление, макс.
    "net.ipv4.tcp_mem = 25600 51200 102400" # Параметры памяти TCP: мин., давление, макс.
    "net.ipv4.tcp_rmem = 4096 87380 67108864" # Размеры буфера приема TCP: мин., дефолт, макс.
    "net.ipv4.tcp_wmem = 4096 65536 67108864" # Размеры буфера отправки TCP: мин., дефолт, макс.
    "net.ipv4.tcp_mtu_probing = 1" # Включает пробирование MTU, чтобы избежать фрагментации пакетов
    "net.ipv4.tcp_congestion_control = bbr" # Включает BBR как алгоритм контроля конгестии
)

for setting in "${settings[@]}"; do
    echo "$setting" | sudo tee -a /etc/sysctl.conf
done

echo "Применение изменений..."
sudo sysctl -p

echo "Изменения успешно применены. Сервер будет перезагружен через 5 секунд..."
sleep 5
sudo reboot
