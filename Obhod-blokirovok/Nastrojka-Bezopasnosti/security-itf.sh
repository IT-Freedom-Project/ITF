#!/bin/bash
echo "Скрипт для настройки безопасности VPS от IT Freedom Project v0.80(https://www.youtube.com/@it-freedom-project), (https://github.com/IT-Freedom-Project/Youtube)"

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
    local valid=true

    if [[ ${#password} -lt 16 ]]; then
        echo "Пароль должен быть не менее 16 символов."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[a-zа-я]"; then
        echo "Пароль должен содержать хотя бы одну букву нижнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[A-ZА-Я]"; then
        echo "Пароль должен содержать хотя бы одну букву верхнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[0-9]"; then
        echo "Пароль должен содержать хотя бы одну цифру."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[[:punct:]]"; then
        echo "Пароль должен содержать хотя бы один специальный символ."
        valid=false
    fi

    if ! $valid; then
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
        if [ "$password" != "$password_confirm" ]; then
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

# Функция для перезапуска SSH службы с учетом версии Ubuntu
function restart_ssh_service() {
    if run_command "systemctl list-units --type=service | grep -q sshd.service"; then
        run_command "sudo systemctl restart sshd"
    else
        run_command "sudo systemctl restart ssh"
    fi
}

# Функция для запроса ответа yes/no с проверкой
function prompt_yes_no() {
    local prompt=$1
    local response
    while true; do
        read -p "$prompt (yes/no): " response
        case "$response" in
            [Yy][Ee][Ss]|[Yy])
                echo "yes"
                return 0
                ;;
            [Nn][Oo]|[Nn])
                echo "no"
                return 1
                ;;
            *)
                echo "Пожалуйста, введите 'yes' или 'no'."
                ;;
        esac
    done
}

# Функция для проверки порта SSH
function validate_ssh_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# Функция для отключения ufw перед сменой порта SSH
function disable_ufw_if_active() {
    if run_command "sudo ufw status | grep -q 'Status: active'"; then
        echo "UFW активен. Отключаем UFW перед сменой порта SSH, чтобы избежать блокировки."
        run_command "sudo ufw disable"
    fi
}

# Функция для настройки безопасности на VPS
function secure_vps() {
    # Обновление системы
    if [ -z "$UPDATE_SYSTEM" ];then
        UPDATE_SYSTEM=$(prompt_yes_no "Хотите обновить систему?")
    fi
    if [ "$UPDATE_SYSTEM" == "yes" ];then
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
        run_command "sudo DEBIAN_FRONTEND=noninteractive unattended-upgrade"
    fi

    # Изменение пароля root
    if [ -z "$CHANGE_ROOT_PASSWORD" ];then
        CHANGE_ROOT_PASSWORD=$(prompt_yes_no "Хотите изменить пароль root?")
    fi
    if [ "$CHANGE_ROOT_PASSWORD" == "yes" ];then
        while true; do
            if [ -z "$ROOT_PASSWORD" ];then
                read -s -p "Введите новый пароль для root: " ROOT_PASSWORD
                echo
                validate_password "$ROOT_PASSWORD"
                if [ $? -ne 0 ];then
                    ROOT_PASSWORD=""
                    continue
                fi
                read -s -p "Повторите новый пароль для root: " ROOT_PASSWORD_CONFIRM
                echo
                if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ];then
                    echo "Пароли не совпадают. Попробуйте снова."
                    ROOT_PASSWORD=""
                    continue
                fi
            fi
            break
        done
        run_command "echo 'root:$ROOT_PASSWORD' | sudo chpasswd"
        if [ $? -eq 0 ];then
            echo "Пароль root успешно изменен."
        else
            echo "Не удалось изменить пароль root."
        fi
    fi

    # Создание новых пользователей
    while true; do
        if ! CREATE_USER=$(prompt_yes_no "Хотите создать нового пользователя?"); then
            break
        fi

        while true; do
            read -p "Введите имя пользователя: " username
            validate_username "$username"
            if [ $? -eq 0 ]; then
                break
            fi
        done

        if id "$username" &>/dev/null; then
            echo "Пользователь $username уже существует."
            if CHANGE_USER_PASSWORD=$(prompt_yes_no "Хотите изменить пароль для пользователя $username?"); then
                change_user_password "$username"
            fi

            if sudo grep -q "$username ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/*; then
                if REMOVE_USER_NOPASSWD=$(prompt_yes_no "Хотите исключить пользователя $username из группы для выполнения команд без пароля?"); then
                    remove_user_nopasswd "$username"
                fi
            else
                if ADD_USER_NOPASSWD=$(prompt_yes_no "Хотите добавить пользователя $username в группу для выполнения команд без пароля?"); then
                    add_user_nopasswd "$username"
                fi
            fi
        else
            while true; do
                read -s -p "Введите пароль для пользователя $username: " password
                echo
                validate_password "$password"
                if [ $? -ne 0 ];then
                    password=""
                    continue
                fi
                read -s -p "Повторите пароль для пользователя $username: " password_confirm
                echo
                if [ "$password" != "$password_confirm" ];then
                    echo "Пароли не совпадают. Попробуйте снова."
                    password=""
                    continue
                fi
                break
            done
            if nopass=$(prompt_yes_no "Разрешить выполнение команд без пароля для $username?"); then
                create_user "$username" "$password" "$nopass"
            fi
        fi
    done

    # Проверка текущего состояния входа root по SSH
    ROOT_SSH_STATUS=$(run_command "sudo grep '^PermitRootLogin' /etc/ssh/sshd_config")
    if [[ "$ROOT_SSH_STATUS" == "PermitRootLogin no" ]];then
        if ENABLE_ROOT_SSH=$(prompt_yes_no "Вход root по SSH отключен. Хотите включить вход root по SSH?");then
            run_command "sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
            restart_ssh_service
            echo "Вход root по SSH включен."
        fi
    else
        if DISABLE_ROOT_SSH=$(prompt_yes_no "Хотите отключить вход root по SSH?");then
            run_command "sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
            restart_ssh_service
            echo "Вход root по SSH отключен."
        fi
    fi

    # Изменение порта SSH
    CURRENT_SSH_PORT=22
    if [ -z "$CHANGE_SSH_PORT" ];then
        CHANGE_SSH_PORT=$(prompt_yes_no "Хотите изменить порт SSH?")
    fi
    if [ "$CHANGE_SSH_PORT" == "yes" ];then
        disable_ufw_if_active # Отключение ufw перед изменением порта SSH
        while true; do
            if [ -z "$NEW_SSH_PORT" ];then
                read -p "Введите новый порт SSH (от 1024 до 65535): " NEW_SSH_PORT
            fi
            if validate_ssh_port "$NEW_SSH_PORT";then
                break
            else
                echo "Недопустимый порт. Порт должен быть в диапазоне от 1024 до 65535."
                NEW_SSH_PORT=""
            fi
        done
        run_command "sudo sed -i 's/#Port 22/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config"
        restart_ssh_service
        echo "Порт SSH изменен на $NEW_SSH_PORT."
        CURRENT_SSH_PORT=$NEW_SSH_PORT
    fi

    # Настройка ufw
    if [ -z "$CONFIGURE_UFW" ];then
        CONFIGURE_UFW=$(prompt_yes_no "Хотите настроить ufw?")
    fi
    if [ "$CONFIGURE_UFW" == "yes" ];then
        run_command "sudo apt install -yq ufw"
        echo "y" | run_command "sudo ufw allow $CURRENT_SSH_PORT/tcp"
        echo "y" | run_command "sudo ufw enable"
        echo "ufw настроен и включен."
    fi

    # Настройка fail2ban
    if [ -z "$CONFIGURE_FAIL2BAN" ];then
        CONFIGURE_FAIL2BAN=$(prompt_yes_no "Хотите настроить fail2ban?")
    fi
    if [ "$CONFIGURE_FAIL2BAN" == "yes" ];then
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

    # Остановка qemu-guest-agent и других сервисов
    SERVICES=("qemu-guest-agent")
    for service in "${SERVICES[@]}"; do
        if dpkg -l | grep -qw "$service";then
            SERVICE_STATUS=$(run_command "sudo systemctl is-active $service")
            if [ "$SERVICE_STATUS" == "active" ];then
                if STOP_SERVICE=$(prompt_yes_no "$service установлен и активен. Хотите остановить и отключить его?");then
                    run_command "sudo systemctl stop $service"
                    run_command "sudo systemctl disable $service"
                    run_command "sudo systemctl mask $service"
                    echo "$service остановлен, отключен и замаскирован."
                fi
            else
                if START_SERVICE=$(prompt_yes_no "$service установлен, но не активен. Хотите включить его?");then
                    run_command "sudo systemctl unmask $service"
                    run_command "sudo systemctl enable $service"
                    run_command "sudo systemctl start $service"
                    echo "$service включен и активен."
                fi
            fi
        fi
    done
}

# Главная функция
function main() {
    read -p "Выберите режим работы (local/ssh): " MODE

    if [ "$MODE" == "ssh" ];then
        if [ -z "$SSH_HOST" ];then
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

secure_vps
