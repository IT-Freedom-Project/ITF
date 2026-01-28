#!/bin/bash


# Пути к файлам конфигурации
RULES_SCRIPT="/etc/iptables/direct_rules.sh"
LOADER_SCRIPT="/usr/local/bin/load-udp-proxy.sh"
SERVICE_FILE="/etc/systemd/system/udp-proxy-load.service"

if [[ $EUID -ne 0 ]]; then
   echo "Ошибка: Запустите от root (sudo)"; exit 1
fi

# Функция точечной очистки только наших правил из памяти
clear_iptables_safe() {
    iptables -t nat -S | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables -t nat $line; done 2>/dev/null
    iptables -S FORWARD | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables $line; done 2>/dev/null
}

setup_service() {
    mkdir -p /etc/iptables
    [ ! -f "$RULES_SCRIPT" ] && touch "$RULES_SCRIPT"
    chmod +x "$RULES_SCRIPT"

    cat <<EOF > "$LOADER_SCRIPT"
#!/bin/bash
modprobe iptable_nat 2>/dev/null
modprobe br_netfilter 2>/dev/null
modprobe xt_comment 2>/dev/null
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sleep 5
iptables -t nat -S | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables -t nat \$line; done 2>/dev/null
iptables -S FORWARD | grep "udp-proxy" | sed 's/-A/-D/' | while read line; do iptables \$line; done 2>/dev/null
if [ -s "$RULES_SCRIPT" ]; then
    /bin/bash "$RULES_SCRIPT"
fi
EOF
    chmod +x "$LOADER_SCRIPT"

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Universal UDP Proxy Loader
After=network-online.target local-fs.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=$LOADER_SCRIPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable udp-proxy-load.service >/dev/null 2>&1
}

show_list() {
    clear
    echo "=================================================="
    echo "--- Статус Forwarding (должен быть 1) ---"
    sysctl net.ipv4.ip_forward
    echo ""
    echo "--- Активные правила UDP Proxy ---"
    iptables -t nat -L -n -v --line-numbers | grep "udp-proxy" || echo "Активных правил NAT нет."
    iptables -L FORWARD -n -v --line-numbers | grep "udp-proxy" || echo "Активных правил FORWARD нет."
    echo "=================================================="
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}

add_rule() {
    setup_service
    clear_iptables_safe
    echo "--- Добавление нового правила ---"
    read -p "Локальный порт (напр. 50600:50700 или 50676): " LPORT
    read -p "IP цели: " TIP
    read -p "Порт цели (напр. 50600:50700 или 50676): " TPORT

    if [[ -z "$LPORT" || -z "$TIP" || -z "$TPORT" ]]; then
        echo "Ошибка: Все поля должны быть заполнены!"
        sleep 2; return
    fi

    LPORT_IPT=$(echo "$LPORT" | tr '-' ':')
    TPORT_IPT=$(echo "$TPORT" | tr '-' ':')
    DNAT_TARGET=$(echo "$TPORT_IPT" | tr ':' '-')

    C1="iptables -t nat -A PREROUTING -p udp --dport $LPORT_IPT -m comment --comment \"udp-proxy\" -j DNAT --to-destination $TIP:$DNAT_TARGET"
    C2="iptables -t nat -A POSTROUTING -p udp -d $TIP --dport $TPORT_IPT -m comment --comment \"udp-proxy\" -j MASQUERADE"
    C3="iptables -A FORWARD -p udp -d $TIP --dport $TPORT_IPT -m comment --comment \"udp-proxy\" -j ACCEPT"
    C4="iptables -A FORWARD -p udp -s $TIP --sport $TPORT_IPT -m comment --comment \"udp-proxy\" -j ACCEPT"

    echo 1 > /proc/sys/net/ipv4/ip_forward
    eval "$C1" && eval "$C2" && eval "$C3" && eval "$C4"
    
    echo "$C1" >> "$RULES_SCRIPT"
    echo "$C2" >> "$RULES_SCRIPT"
    echo "$C3" >> "$RULES_SCRIPT"
    echo "$C4" >> "$RULES_SCRIPT"

    echo "Правила успешно добавлены!"
    sleep 2
}

delete_all() {
    clear
    echo "!!! ВНИМАНИЕ !!!"
    echo "Это удалит ВСЕ правила с меткой 'udp-proxy' и отключит автозагрузку."
    read -p "Вы уверены? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "Очистка..."
        systemctl stop udp-proxy-load.service 2>/dev/null
        systemctl disable udp-proxy-load.service 2>/dev/null
        clear_iptables_safe
        rm -f "$RULES_SCRIPT"
        echo "Система очищена."
    else
        echo "Отмена удаления."
    fi
    sleep 2
}

# ГЛАВНОЕ МЕНЮ
while true; do
    clear
    echo "========================================"
    echo "   Управление UDP Proxy v1 (Ubuntu 22/24, Debian)  "
    echo "     https://github.com/IT-Freedom-Project/ITF "
    echo "========================================"
    echo "1) Посмотреть существующие правила"
    echo "2) Добавить новое правило"
    echo "3) Удалить ВСЕ правила"
    echo "4) Выход"
    echo "========================================"
    read -p "Выберите действие [1-4]: " choice

    case $choice in
        1) show_list ;;
        2) add_rule ;;
        3) delete_all ;;
        4) clear; exit 0 ;;
        *) echo "Неверный выбор, попробуйте снова."; sleep 1 ;;
    esac
done
