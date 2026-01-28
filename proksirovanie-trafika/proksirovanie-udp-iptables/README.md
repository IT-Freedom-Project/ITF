# Настройка проксирования UDP через iptables (Ubuntu/Debian)

Скрипт в режиме диалога настраивает сеть промежуточного сервера для проксирования UDP трафика (любого, может быть полезно для ряда протоколов), текущие правила можно смотреть, а также полностью их удалять. Должно быть совместимо с [проксированием TCP через HAProxy](https://github.com/IT-Freedom-Project/ITF/tree/main/proksirovanie-trafika/proksirovanie-tcp-haproxy).

Для запуска скрипта выполняем эту команду:\
\
```sudo wget -O udp-proxy.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/refs/heads/main/proksirovanie-trafika/proksirovanie-udp-iptables/udp-proxy.sh && sudo bash udp-proxy.sh```\
\
или эту: \
\
```sudo curl -o udp-proxy.sh https://raw.githubusercontent.com/IT-Freedom-Project/ITF/refs/heads/main/proksirovanie-trafika/proksirovanie-udp-iptables/udp-proxy.sh && sudo bash udp-proxy.sh```

