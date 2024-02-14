Скрипт оптимизирует сетевой стек сервера Linux (TCP + BBR, UDP). Он удаляет (при наличии) и пишет заново параметры с нужными значениями в /etc/security/limits.conf и добавляет или меняет на нужные значения параметры в /etc/sysctl.conf\
\
Для запуска скрипта выполняем эту команду:\
\
```wget -O bbr-itf.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/main/Obhod-blokirovok/Nastrojka-BBR/bbr-itf.sh && sudo bash bbr-itf.sh```\
\
или эту: \
\
```curl -o bbr-itf.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/main/Obhod-blokirovok/Nastrojka-BBR/bbr-itf.sh && sudo bash bbr-itf.sh``` \
\
Или делаем вручную:

1. Выполняем команду:\
\
```sudo nano /etc/security/limits.conf```

2. Вставляем в конец файла текст:

\# Устанавливаем мягкий лимит на количество открытых файлов\
\* soft nofile 51200 \
\# Устанавливаем жесткий лимит на количество открытых файлов\
\* hard nofile 51200 \
\# Мягкий лимит для root\
root soft nofile 51200\
\# Жесткий лимит для root\
root hard nofile 51200

3. Нажимаем CTRL+O (сохраняем), затем Enter (подтверждаем), потом CTRL+X (выходим)
4. Выполняем команду (установка лимита открытых файлов):\
\
```ulimit -n 51200```
5. Выполняем команду:\
\
```sudo nano /etc/sysctl.conf```
6. Вставляем в конец файла текст:
\
\# Максимальное количество открытых файлов для всей системы\
fs.file-max = 51200\
\# Максимальный размер буфера приема для всех сокетов\
net.core.rmem_max = 67108864\
\# Максимальный размер буфера отправки для всех сокетов\
net.core.wmem_max = 67108864\
\# Максимальное количество пакетов в очереди интерфейса перед обработкой\
net.core.netdev_max_backlog = 10000\
\# Лимит размера очереди запросов на установление соединения\
net.core.somaxconn = 4096\
\# Планировщик очереди по умолчанию, используемый для управления перегрузками\
net.core.default_qdisc = fq\
\# Включение SYN cookies для защиты от SYN flood атак\
net.ipv4.tcp_syncookies = 1\
\# Позволяет повторно использовать TIME-WAIT сокеты для новых соединений\
net.ipv4.tcp_tw_reuse = 1\
\# Таймаут для закрытия соединения на стороне, отправившей FIN\
net.ipv4.tcp_fin_timeout = 30\
\# Время в секундах до начала отправки keepalive пакетов\
net.ipv4.tcp_keepalive_time = 1200\
\# Количество keepalive проб, прежде чем соединение будет считаться разорванным\
net.ipv4.tcp_keepalive_probes = 5\
\# Интервал между keepalive пробами\
net.ipv4.tcp_keepalive_intvl = 30\
\# Максимальное количество соединений в очереди на установление\
net.ipv4.tcp_max_syn_backlog = 8192\
\# Диапазон портов, используемых для исходящих соединений\
net.ipv4.ip_local_port_range = 10000 65000\
\# Отключает slow start после идлового состояния соединения\
net.ipv4.tcp_slow_start_after_idle = 0\
\# Максимальное количество сокетов в состоянии TIME-WAIT\
net.ipv4.tcp_max_tw_buckets = 5000\
\# Включает TCP Fast Open на стороне клиента и сервера\
net.ipv4.tcp_fastopen = 3\
\# Параметры памяти UDP: мин., давление, макс.\
net.ipv4.udp_mem = 25600 51200 102400\
\# Параметры памяти TCP: мин., давление, макс.\
net.ipv4.tcp_mem = 25600 51200 102400\
\# Размеры буфера приема TCP: мин., дефолт, макс.\
net.ipv4.tcp_rmem = 4096 87380 67108864\
\# Размеры буфера отправки TCP: мин., дефолт, макс.\
net.ipv4.tcp_wmem = 4096 65536 67108864\
\# Включает пробирование MTU, чтобы избежать фрагментации пакетов\
net.ipv4.tcp_mtu_probing = 1\
\# Включает BBR как алгоритм контроля конгестии\
net.ipv4.tcp_congestion_control = bbr

7. Нажимаем CTRL+O (сохраняем), затем Enter (подтверждаем), потом CTRL+X (выходим)
8. Выполняем команду:\
\
```sudo sysctl -p```

9. Выполняем команду для перезагрузки:\
\
```sudo reboot```
