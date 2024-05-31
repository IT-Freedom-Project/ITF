#!/bin/bash

# Переменные для SSH подключения (можно оставить пустыми для запроса при выполнении скрипта)
SSH_HOST=""
SSH_USER=""
SSH_PORT=22
SSH_PASSWORD=""

# Переменные для создания пользователей (можно оставить пустыми для запроса при выполнении скрипта)
declare -A USERS=(
    # ["namenewuser1"]="nameuser:passworduser:no"
    # ["namenewuser2"]="newuser:passworduser2:yes"
)

# Вопросы и ответы (можно оставить пустыми для запроса при выполнении скрипта)
UPDATE_SYSTEM=""  # yes/no
CHANGE_ROOT_PASSWORD=""  # yes/no
ROOT_PASSWORD=""
DISABLE_ROOT_SSH=""  # yes/no
CHANGE_SSH_PORT=""  # yes/no
NEW_SSH_PORT=22
CONFIGURE_UFW=""  # yes/no
CONFIGURE_FAIL2BAN=""  # yes/no

# Функция для выполнения команды на удаленной машине через SSH
function ssh_command() {
    local cmd=$1
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$SSH_HOST" "$cmd"
}

# Функция для выполнения команды локально или через SSH
function run_command() {
    if [ "$MODE" == "ssh" ]; then
        ssh_command "$1"
    else
        eval "$1"
    fi
}

# Функция для проверки имени пользователя
function validate_username() {
    local username=$1
    if [[ ${#username} -lt 1 || ${#username} -gt 32 ]]; then
        echo "Имя пользователя должно быть от 1 до 32 символов."
        return 1
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Имя пользователя должно начинаться с буквы или подчеркивания, и содержать только строчные буквы, цифры, дефисы и подчеркивания."
        return 1
    fi
    return 0
}

# Функция для проверки пароля
function validate_password() {
    local password=$1
    if [[ ${#password} -lt 16 ]]; then
        echo "Пароль должен быть не менее 16 символов."
        return 1
    fi
    if ! [[ "$password" =~ [a-z] ]]; then
        echo "Пароль должен содержать хотя бы одну букву нижнего регистра."
        return 1
    fi
    if ! [[ "$password" =~ [A-Z] ]]; then
        echo "Пароль должен содержать хотя бы одну букву верхнего регистра."
        return 1
    fi
    if ! [[ "$password" =~ [0-9] ]]; then
        echo "Пароль должен содержать хотя бы одну цифру."
        return 1
    fi
    if ! [[ "$password" =~ [[:punct:]] ]]; then
        echo "Пароль должен содержать хотя бы один специальный символ."
        return 1
    fi
    return 0
}

# Функция для создания пользователя
function create_user() {
    local username=$1
    local password=$2
    local nopass=$3

    run_command "sudo adduser --disabled-password --gecos '' $username"
    run_command "echo '$username:$password' | sudo chpasswd"
    run_command "sudo usermod -aG sudo $username"
    if [ "$nopass" == "yes" ]; then
        run_command "echo '$username ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$username"
    fi
    echo "Пользователь $username создан."
}

# Функция для настройки безопасности на VPS
function secure_vps() {
    # Обновление системы
    if [ -z "$UPDATE_SYSTEM" ]; then
        read -p "Хотите обновить систему? (yes/no): " UPDATE_SYSTEM
    fi
    if [ "$UPDATE_SYSTEM" == "yes" ]; then
        echo "Обновляем систему..."
        run_command "sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -yq"
    fi

    # Изменение пароля root
    if [ -z "$CHANGE_ROOT_PASSWORD" ]; then
        read -p "Хотите изменить пароль root? (yes/no): " CHANGE_ROOT_PASSWORD
    fi
    if [ "$CHANGE_ROOT_PASSWORD" == "yes" ]; then
        while true; do
            if [ -z "$ROOT_PASSWORD" ]; then
                read -s -p "Введите новый пароль для root: " ROOT_PASSWORD
                echo
                validate_password "$ROOT_PASSWORD"
                if [ $? -ne 0 ]; then
                    ROOT_PASSWORD=""
                    continue
                fi
                read -s -p "Повторите новый пароль для root: " ROOT_PASSWORD_CONFIRM
                echo
                if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
                    echo "Пароли не совпадают. Попробуйте снова."
                    ROOT_PASSWORD=""
                    continue
                fi
            fi
            break
        done
        run_command "echo 'root:$ROOT_PASSWORD' | sudo chpasswd"
        echo "Пароль root успешно изменен."
    fi

    # Создание новых пользователей
    while true; do
        read -p "Хотите создать нового пользователя? (yes/no): " CREATE_USER
        if [ "$CREATE_USER" == "no" ]; then
            break
        fi

        while true; do
            read -p "Введите имя пользователя: " username
            validate_username "$username"
            if [ $? -eq 0 ]; then
                break
            fi
        done

        while true; do
            read -s -p "Введите пароль для пользователя $username: " password
            echo
            validate_password "$password"
            if [ $? -ne 0 ]; then
                password=""
                continue
            fi
            read -s -p "Повторите пароль для пользователя $username: " password_confirm
            echo
            if [ "$password" != "$password_confirm" ]; then
                echo "Пароли не совпадают. Попробуйте снова."
                password=""
                continue
            fi
            break
        done
        read -p "Разрешить выполнение команд без пароля для $username? (yes/no): " nopass
        create_user "$username" "$password" "$nopass"
    done

    # Отключение входа root по SSH
    if [ -z "$DISABLE_ROOT_SSH" ]; then
        read -p "Хотите отключить вход root по SSH? (yes/no): " DISABLE_ROOT_SSH
    fi
    if [ "$DISABLE_ROOT_SSH" == "yes" ]; then
        run_command "sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
        run_command "sudo systemctl restart sshd"
        echo "Вход root по SSH отключен."
    else
        run_command "sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
        run_command "sudo systemctl restart sshd"
        echo "Вход root по SSH включен."
    fi

    # Изменение порта SSH
    CURRENT_SSH_PORT=22
    if [ -z "$CHANGE_SSH_PORT" ]; then
        read -p "Хотите изменить порт SSH? (yes/no): " CHANGE_SSH_PORT
    fi
    if [ "$CHANGE_SSH_PORT" == "yes" ]; then
        if [ -z "$NEW_SSH_PORT" ]; then
            read -p "Введите новый порт SSH: " NEW_SSH_PORT
        fi
        run_command "sudo sed -i 's/#Port 22/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config"
        run_command "sudo systemctl restart sshd"
        echo "Порт SSH изменен на $NEW_SSH_PORT."
        CURRENT_SSH_PORT=$NEW_SSH_PORT
    fi

    # Настройка ufw
    if [ -z "$CONFIGURE_UFW" ]; then
        read -p "Хотите настроить ufw? (yes/no): " CONFIGURE_UFW
    fi
    if [ "$CONFIGURE_UFW" == "yes" ]; then
        run_command "sudo apt install ufw -y"
        run_command "sudo ufw allow $CURRENT_SSH_PORT/tcp"
        run_command "sudo ufw enable"
        echo "ufw настроен и включен."
    fi

    # Настройка fail2ban
    if [ -z "$CONFIGURE_FAIL2BAN" ]; then
        read -p "Хотите настроить fail2ban? (yes/no): " CONFIGURE_FAIL2BAN
    fi
    if [ "$CONFIGURE_FAIL2BAN" == "yes" ]; then
        run_command "sudo apt install fail2ban -y"
        run_command "sudo systemctl enable fail2ban"
        run_command "sudo systemctl start fail2ban"
        run_command "sudo bash -c 'cat <<EOT > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $CURRENT_SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOT'"
        run_command "sudo systemctl restart fail2ban"
        echo "fail2ban установлен и настроен."
    fi
}

# Главная функция
function main() {
    read -p "Выберите режим работы (local/ssh): " MODE

    if [ "$MODE" == "ssh" ]; then
        if [ -z "$SSH_HOST" ]; then
            read -p "Введите хост SSH: " SSH_HOST
        fi
        if [ -z "$SSH_USER" ];then
            read -p "Введите имя пользователя SSH: " SSH_USER
        fi
        if [ -z "$SSH_PASSWORD" ];then
            read -s -p "Введите пароль SSH: " SSH_PASSWORD
            echo
        fi
    fi

    secure_vps
}

main
