# Настройка проксирования UDP через iptables (Ubuntu/Debian)

Скрипт в режиме диалога настраивает сеть промежуточного сервера для проксирования UDP трафика (любого, может быть полезно для ряда протоколов), текущие правила можно смотреть, а также полностью их удалять. Должно быть совместимо с [проксированием TCP через HAProxy](https://github.com/IT-Freedom-Project/ITF/tree/main/proksirovanie-trafika/proksirovanie-tcp-haproxy). Лучше выполнять от root.

Для запуска скрипта выполняем эту команду:\
\
```sudo wget -O udp-proxy.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/refs/heads/main/proksirovanie-trafika/proksirovanie-udp-iptables/udp-proxy.sh && sudo bash udp-proxy.sh```\
\
или эту: \
\
```sudo curl -o udp-proxy.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/refs/heads/main/proksirovanie-trafika/proksirovanie-udp-iptables/udp-proxy.sh && sudo bash udp-proxy.sh```\
\
Или настройте вручную:

1. **Включение маршрутизации (IP Forwarding)**

Выполните эту команду, чтобы разрешить серверу пересылать трафик. Она создаст файл конфигурации и сразу применит настройки:

```echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-udp-proxy.conf && sudo sysctl -p /etc/sysctl.d/99-udp-proxy.conf```

2. **Создание загрузчика правил**

Этот скрипт подготавливает ядро и очищает память перед применением ваших правил:
```
sudo mkdir -p /etc/iptables
sudo tee /usr/local/bin/load-udp-proxy.sh <<'EOF'
#!/bin/bash
# 1. Загрузка критических модулей ядра
modprobe iptable_nat
modprobe nf_nat
modprobe nf_conntrack
modprobe br_netfilter
modprobe xt_comment

# 2. Принудительное разрешение форвардинга

echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -P FORWARD ACCEPT

# 3. Очистка старых правил с меткой "udp-proxy"

iptables -t nat -S | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables -t nat $line; done 2>/dev/null
iptables -S FORWARD | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables $line; done 2>/dev/null

# 4. Запуск файла с вашими правилами

if [ -s "/etc/iptables/direct_rules.sh" ]; then
    /bin/bash "/etc/iptables/direct_rules.sh"
fi
EOF
sudo chmod +x /usr/local/bin/load-udp-proxy.sh
```
3. **Настройка автозагрузки (Systemd)**

Чтобы прокси работал после перезагрузки сервера:

```
sudo tee /etc/systemd/system/udp-proxy-load.service <<EOF
[Unit]
Description=Universal UDP Proxy Loader
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/load-udp-proxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable udp-proxy-load.service
```

4. **Добавление и Удаление правил**

Чтобы добавить правила:

Замените 50600:50700 (ваш порт или диапазон. Диапазон на вход и выход должен быть один) и 1.2.3.4 (целевой IP) на свои. Важно: в PREROUTING и POSTROUTING используйте двоеточие для диапазонов, а в DNAT — дефис.

```
# Очищаем файл перед добавлением

sudo truncate -s 0 /etc/iptables/direct_rules.sh

# **Записываем новые правила**

sudo tee -a /etc/iptables/direct_rules.sh <<EOF
iptables -t nat -A PREROUTING -p udp --dport 50600:50700 -m comment --comment "udp-proxy" -j DNAT --to-destination 1.2.3.4:50600-50700
iptables -t nat -A POSTROUTING -p udp -d 1.2.3.4 --dport 50600:50700 -m comment --comment "udp-proxy" -j MASQUERADE
iptables -A FORWARD -p udp -d 1.2.3.4 --dport 50600:50700 -m comment --comment "udp-proxy" -j ACCEPT
iptables -A FORWARD -p udp -s 1.2.3.4 --sport 50600:50700 -m comment --comment "udp-proxy" -j ACCEPT
EOF

# ПРИМЕНЯЕМ ИЗМЕНЕНИЯ
sudo systemctl restart udp-proxy-load.service
```

**Чтобы удалить ВСЕ правила:**

Если вы хотите полностью остановить проксирование и очистить память:

```
# 1. Очищаем файл правил
sudo truncate -s 0 /etc/iptables/direct_rules.sh

# 2. Перезапускаем службу (она удалит правила из таблиц)
sudo systemctl restart udp-proxy-load.service

# 3. Полный сброс активных соединений (теперь модули не заняты и команда сработает)
sudo modprobe -r xt_MASQUERADE nf_nat nf_conntrack 2>/dev/null
sudo modprobe nf_conntrack
```
