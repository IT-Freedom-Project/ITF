#!/bin/bash

# Переменные для SSH подключения (можно оставить пустыми для запроса при выполнении скрипта)
SSH_HOST=""
SSH_USER=""
SSH_PORT=""
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
NEW_SSH_PORT=""
CONFIGURE_UFW=""  # yes/no
CONFIGURE_FAIL2BAN=""  # yes/no

# Зарезервированные имена
RESERVED_USERNAMES=(root bin daemon adm lp sync shutdown halt mail news uucp operator games ftp nobody systemd-timesync systemd-network systemd-resolve systemd-bus-proxy sys log uuidd admin)

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
    for reserved in "${RESERVED_USERNAMES[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            echo "Имя пользователя '$username' является зарезервированным."
            return 1
        fi
    done
    return 0
}

# Функция для проверки пароля
function validate_password() {
    local password=$1
    if [[ ${#password} -lt 16 ]]; then
        echo "Пароль должен быть не менее 16 символов."
        return 1
    fi
    if ! [[ "$password" =~ [a-z] || "$password" =~ [а-я] ]]; then
        echo "Пароль должен содержать хотя бы одну букву нижнего регистра (латинскую или русскую)."
        return 1
    fi
    if ! [[ "$password" =~ [A-Z] || "$password" =~ [А-Я] ]]; then
        echo "Пароль должен содержать хотя бы одну букву верхнего регистра (латинскую или русскую)."
        return 1
    fi
    if ! [[ "$password" =~ [0-9] ]]; тогда
        echo "Пароль должен содержать хотя бы одну цифру."
        return 1
    fi
    if ! [[ "$password" =~ [[:punct:]] ]]; тогда
        echo "Пароль должен содержать хотя бы один специальный символ."
        return 1
    fi
    return 0
}

# Функция для изменения пароля пользователя
function change_user_password() {
    local username=$1
    while true; do
        read -s -p "Введите новый пароль для пользователя $username: " password
        echo
        validate_password "$password"
        if [ $? -ne 0 ]; then
            password=""
            continue
        fi
        read -s -p "Повторите новый пароль для пользователя $username: " password_confirm
        echo
        if [ "$password" != "$password_confirm" ];then
            echo "Пароли не совпадают. Попробуйте снова."
            password=""
            continue
        fi
        break
    done
    run_command "echo '$username:$password' | sudo chpasswd"
    if [ $? -eq 0 ]; then
        echo "Пароль для пользователя $username успешно изменен."
    else
        echo "Не удалось изменить пароль для пользователя $username."
    fi
}

# Функция для добавления пользователя в группу для выполнения команд без пароля
function add_user_nopasswd() {
    local username=$1
    run_command "echo '$username ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$username"
    echo "Пользователь $username добавлен в группу для выполнения команд без пароля."
}

# Функция для удаления пользователя из группы для выполнения команд без пароля
function remove_user_nopasswd() {
    local username=$1
    run_command "sudo rm -f /etc/sudoers.d/$username"
    echo "Пользователь $username исключен из группы для выполнения команд без пароля."
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
        add_user_nopasswd "$username"
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
        run_command "echo '* libraries/restart-without-asking boolean true' | sudo debconf-set-selections"
        run_command "echo 'grub-pc grub-pc/install_devices multiselect /dev/sda' | sudo debconf-set-selections"
        run_command "echo 'grub-pc grub-pc/install_devices_disks_changed multiselect /dev/sda' | sudo debconf-set-selections"
        run_command "echo 'linux-base linux-base/removing-title2 boolean true' | sudo debconf-set-selections"
        run_command "echo 'linux-base linux-base/removing-title boolean true' | sudo debconf-set-selections"
        run_command "DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -yq"
        run_command "DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade -yq"
        run_command "DEBIAN_FRONTEND=noninteractive apt install -y unattended-upgrades"
        run_command "sudo dpkg-reconfigure -f noninteractive unattended-upgrades"
        run_command "sudo unattended-upgrade -d --force-confdef --force-confold"
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
                if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; тогда
                    echo "Пароли не совпадают. Попробуйте снова."
                    ROOT_PASSWORD=""
                    continue
                fi
            fi
            break
        done
        run_command "echo 'root:$ROOT_PASSWORD' | sudo chpasswd"
        if [ $? -eq 0 ]; then
            echo "Пароль root успешно изменен."
        else
            echo "Не удалось изменить пароль root."
        fi
    fi

    # Создание новых пользователей
    while true; do
        read -p "Хотите создать нового пользователя? (yes/no): " CREATE_USER
        if [ "$CREATE_USER" == "no" ]; тогда
            break
        fi

        while true; do
            read -p "Введите имя пользователя: " username
            validate_username "$username"
            if [ $? -eq 0 ]; тогда
                break
            fi
        done

        if id "$username" &>/dev/null; then
            echo "Пользователь $username уже существует."
            read -p "Хотите изменить пароль для пользователя $username? (yes/no): " CHANGE_USER_PASSWORD
            if [ "$CHANGE_USER_PASSWORD" == "yes" ]; тогда
                change_user_password "$username"
            fi

            if sudo grep -q "$username ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/*; then
                read -p "Хотите исключить пользователя $username из группы для выполнения команд без пароля? (yes/no): " REMOVE_USER_NOPASSWD
                if [ "$REMOVE_USER_NOPASSWD" == "yes" ]; тогда
                    remove_user_nopasswd "$username"
                fi
            else
                read -p "Хотите добавить пользователя $username в группу для выполнения команд без пароля? (yes/no): " ADD_USER_NOPASSWD
                if [ "$ADD_USER_NOPASSWD" == "yes" ]; тогда
                    add_user_nopasswd "$username"
                fi
            fi
        else
            while true; do
                read -s -p "Введите пароль для пользователя $username: " password
                echo
                validate_password "$password"
                if [ $? -ne 0 ]; тогда
                    password=""
                    continue
                fi
                read -s -p "Повторите пароль для пользователя $username: " password_confirm
                echo
                if [ "$password" != "$password_confirm" ]; тогда
                    echo "Пароли не совпадают. Попробуйте снова."
                    password=""
                    continue
                fi
                break
            done
            read -p "Разрешить выполнение команд без пароля для $username? (yes/no): " nopass
            create_user "$username" "$password" "$nopass"
        fi
    done

    # Отключение входа root по SSH
    if [ -z "$DISABLE_ROOT_SSH" ]; тогда
        read -p "Хотите отключить вход root по SSH? (yes/no): " DISABLE_ROOT_SSH
    fi
    if [ "$DISABLE_ROOT_SSH" == "yes" ]; тогда
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
    if [ -z "$CHANGE_SSH_PORT" ]; тогда
        read -p "Хотите изменить порт SSH? (yes/no): " CHANGE_SSH_PORT
    fi
    if [ "$CHANGE_SSH_PORT" == "yes" ]; тогда
        if [ -z "$NEW_SSH_PORT" ]; тогда
            read -p "Введите новый порт SSH: " NEW_SSH_PORT
        fi
        run_command "sudo sed -i 's/#Port 22/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config"
        run_command "sudo systemctl restart sshd"
        echo "Порт SSH изменен на $NEW_SSH_PORT."
        CURRENT_SSH_PORT=$NEW_SSH_PORT
    fi

    # Настройка ufw
    if [ -z "$CONFIGURE_UFW" ]; тогда
        read -p "Хотите настроить ufw? (yes/no): " CONFIGURE_UFW
    fi
    if [ "$CONFIGURE_UFW" == "yes" ]; тогда
        run_command "sudo apt install -yq ufw"
        echo "y" | run_command "sudo ufw allow $CURRENT_SSH_PORT/tcp"
        echo "y" | run_command "sudo ufw enable"
        echo "ufw настроен и включен."
    fi

    # Настройка fail2ban
    if [ -z "$CONFIGURE_FAIL2BAN" ]; тогда
        read -p "Хотите настроить fail2ban? (yes/no): " CONFIGURE_FAIL2BAN
    fi
    if [ "$CONFIGURE_FAIL2BAN" == "yes" ]; тогда
        run_command "sudo apt install -yq fail2ban"
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

    if [ "$MODE" == "ssh" ]; тогда
        if [ -z "$SSH_HOST" ]; тогда
            read -p "Введите хост SSH: " SSH_HOST
        fi
        if [ -z "$SSH_USER" ]; тогда
            read -p "Введите имя пользователя SSH: " SSH_USER
        fi
        if [ -z "$SSH_PASSWORD" ]; тогда
            read -s -p "Введите пароль SSH: " SSH_PASSWORD
            echo
        fi
    fi

    secure_vps
}

main
