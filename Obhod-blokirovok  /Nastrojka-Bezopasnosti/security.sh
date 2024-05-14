#!/bin/bash

# Переменные конфигурации
NEW_SSH_PORT=
OLD_ROOT_PASSWORD=
NEW_ROOT_PASSWORD=
SERVER_ADDRESS=
ADMIN_USER=  # Имя пользователя для SSH, например admin
ADMIN_PASSWORD=  # Пароль пользователя для SSH, если используется парольная аутентификация
NEW_USER_NAME=
NEW_USER_PASSWORD=

# Функция для запроса данных, если они не предоставлены
request_input() {
    while [[ -z "$NEW_SSH_PORT" || ! "$NEW_SSH_PORT" =~ ^[0-9]+$ || "$NEW_SSH_PORT" -lt 1024 || "$NEW_SSH_PORT" -gt 65535 ]]; do
        read -p "Введите новый порт SSH (1024-65535): " NEW_SSH_PORT
    done

    while [[ -z "$NEW_ROOT_PASSWORD" || "${#NEW_ROOT_PASSWORD}" -lt 12 || ! "$NEW_ROOT_PASSWORD" =~ [A-Z] || ! "$NEW_ROOT_PASSWORD" =~ [a-z] || ! "$NEW_ROOT_PASSWORD" =~ [0-9] || ! "$NEW_ROOT_PASSWORD" =~ [^a-zA-Z0-9] ]]; do
        read -s -p "Введите новый пароль для root: " NEW_ROOT_PASSWORD
        echo
        read -s -p "Подтвердите новый пароль для root: " root_password_confirm
        echo
        if [ "$NEW_ROOT_PASSWORD" != "$root_password_confirm" ]; then
            echo "Пароли не совпадают, попробуйте еще раз."
            NEW_ROOT_PASSWORD=""
        fi
    done

    if [[ -z "$SERVER_ADDRESS" ]]; then
        read -p "Введите адрес удалённого сервера (user@host): " SERVER_ADDRESS
    fi

    while [[ -z "$NEW_USER_NAME" || ! "$NEW_USER_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; do
        read -p "Введите имя нового пользователя (только буквы, цифры и нижние подчеркивания): " NEW_USER_NAME
    done

    while [[ -z "$NEW_USER_PASSWORD" || "${#NEW_USER_PASSWORD}" -lt 12 || ! "$NEW_USER_PASSWORD" =~ [A-Z] || ! "$NEW_USER_PASSWORD" =~ [a-z] || ! "$NEW_USER_PASSWORD" =~ [0-9] || ! "$NEW_USER_PASSWORD" =~ [^a-zA-Z0-9] ]]; do
        read -s -p "Введите пароль для нового пользователя: " NEW_USER_PASSWORD
        echo
        read -s -p "Подтвердите пароль: " user_password_confirm
        echo
        if [ "$NEW_USER_PASSWORD" != "$user_password_confirm" ]; then
            echo "Пароли не совпадают, попробуйте еще раз."
            NEW_USER_PASSWORD=""
        fi
    done
}

# Установка sshpass если не установлен
check_and_install_sshpass() {
    if [[ -n "$ADMIN_PASSWORD" && ! command -v sshpass &>/dev/null ]]; then
        echo "Установка sshpass для автоматического ввода пароля SSH..."
        sudo apt-get install sshpass -y
    fi
}

# Функция для выполнения команд на удалённом или локальном сервере
execute_commands() {
    local commands="$1"
    if [[ -n "$SERVER_ADDRESS" ]]; then
        echo "Выполнение на удалённом сервере: $SERVER_ADDRESS"
        if [[ -n "$ADMIN_PASSWORD" ]]; then
            echo "$ADMIN_PASSWORD" | sshpass ssh -o StrictHostKeyChecking=no $SERVER_ADDRESS "$commands"
        else
            ssh -o StrictHostKeyChecking=no $SERVER_ADDRESS "$commands"
        fi
    else
        echo "Выполнение на локальном сервере"
        eval "$commands"
    fi
}

# Скрипт для настройки системы
SETUP_COMMANDS="
echo 'Обновление списка пакетов и установленных программ...';
sudo apt-get update && sudo apt-get upgrade -y;
echo 'Установка и настройка брандмауэра UFW...';
sudo apt-get install ufw -y;
sudo ufw default deny incoming;
sudo ufw default allow outgoing;
sudo ufw allow ssh;
sudo ufw enable;
sudo sed -i 's/^#*Port .*/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config;
sudo ufw allow $NEW_SSH_PORT/tcp;
sudo ufw delete allow 22/tcp;
sudo service ssh restart;
echo 'root:$NEW_ROOT_PASSWORD' | sudo chpasswd;
sudo useradd -m -s /bin/bash $NEW_USER_NAME;
echo '$NEW_USER_NAME:$NEW_USER_PASSWORD' | sudo chpasswd;
sudo usermod -aG sudo $NEW_USER_NAME;
echo '$NEW_USER_NAME ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$NEW_USER_NAME;
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config;
sudo service ssh restart;
sudo apt-get install fail2ban -y;
sudo systemctl enable fail2ban;
sudo systemctl start fail2ban;
echo '[sshd]' | sudo tee /etc/fail2ban/jail.local;
echo 'enabled = true' | sudo tee -a /etc/fail2ban/jail.local;
echo 'port    = $NEW_SSH_PORT' | sudo tee -a /etc/fail2ban/jail.local;
echo 'filter  = sshd' | sudo tee -a /etc/fail2ban/jail.local;
echo 'logpath = /var/log/auth.log' | sudo tee -a /etc/fail2ban/jail.local;
echo 'maxretry = 5' | sudo tee -a /etc/fail2ban/jail.local;
sudo systemctl restart fail2ban;
"

# Запрашиваем ввод данных, если они не заполнены
request_input

# Проверяем и устанавливаем sshpass, если необходимо
check_and_install_sshpass

# Выполнение команд
execute_commands "$SETUP_COMMANDS"

echo "Базовая настройка безопасности завершена."
