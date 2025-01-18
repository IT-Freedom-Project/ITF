#!/usr/bin/env bash
#======================================================================
# Скрипт для создания, изменения и передачи SSH-ключей (RSA или ED25519),
# а также для редактирования параметров входа по паролю на удалённом сервере.
#
# Поддерживаемые системы: Ubuntu/Debian, Fedora/RHEL/CentOS, macOS, WSL.
# Скрипт может запускаться как от имени root, так и с sudo.
#
# Функционал:
#   1. Проверка наличия SSH и папки ~/.ssh.
#   2. Главное меню для выбора:
#         - выбор типа ключа (RSA или ED25519),
#         - задание имени файла,
#         - если ключ существует, предлагается меню:
#             1) Ввести другое имя
#             2) Отменить
#             3) Перезаписать (создать заново)
#             4) Изменить парольную фразу
#             5) Изменить комментарий
#             6) Передать ключ на сервер
#             7) Добавить ключ в ssh-agent
#             8) Убрать все ключи из ssh-agent
#         - Если ключа нет, он создаётся (с запросом комментария и парольной фразы).
#   3. Передача ключа на сервер:
#         - Сначала используется ssh-copy-id с уже загруженными ключами.
#         - Если возникает ошибка (например, "Too many authentication failures"),
#           ssh-agent очищается (ssh-add -D) и попытка повторяется.
#         - Если ключи не подходят, стандартный ssh-copy-id запросит пароль.
#   4. Финальная настройка:
#         - После успешной передачи ключа выводится текущее состояние параметра 
#           PasswordAuthentication на сервере.
#         - Для не‑root‑пользователя запрашивается sudo-пароль один раз.
#         - После этого локально запрашивается выбор: включить или отключить вход по паролю.
#         - Команды на сервер отправляются через SSH:
#             • Если пользователь root – команды выполняются напрямую.
#             • Иначе – команды выполняются через sudo (каждая команда получает sudo-пароль).
#   5. Интерактивная сессия (только по ключу) для ручного редактирования,
#      если требуется.
#======================================================================

##############################################################################
# 1. Проверка и установка SSH (если отсутствует)
##############################################################################
check_ssh_and_install() {
  if command -v ssh >/dev/null 2>&1; then
    echo "SSH уже установлен."
  else
    echo "SSH не найден. Пытаемся установить..."
    if [[ "$(uname)" == "Darwin" ]]; then
      if command -v brew >/dev/null 2>&1; then
        brew install openssh
      else
        echo "brew не найден. Установите SSH вручную."
        exit 1
      fi
    else
      if command -v apt-get >/dev/null 2>&1; then
        [[ $EUID -eq 0 ]] && apt-get update && apt-get install -y openssh-client || sudo apt-get update && sudo apt-get install -y openssh-client
      elif command -v dnf >/dev/null 2>&1; then
        [[ $EUID -eq 0 ]] && dnf install -y openssh-clients || sudo dnf install -y openssh-clients
      elif command -v yum >/dev/null 2>&1; then
        [[ $EUID -eq 0 ]] && yum install -y openssh-clients || sudo yum install -y openssh-clients
      else
        echo "Не удалось определить пакетный менеджер. Установите SSH вручную."
        exit 1
      fi
    fi
    if ! command -v ssh >/dev/null 2>&1; then
      echo "Не удалось установить SSH. Завершение."
      exit 1
    fi
    echo "SSH установлен."
  fi
}

##############################################################################
# 2. Проверка наличия папки ~/.ssh и её создание
##############################################################################
ensure_ssh_folder() {
  local sshdir="$HOME/.ssh"
  if [[ ! -d "$sshdir" ]]; then
    echo "Папка $sshdir не найдена. Создаём..."
    mkdir -p "$sshdir"
    chmod 700 "$sshdir"
  fi
}

##############################################################################
# 3. Управление ssh-agent: SSHADD и SSHREM
##############################################################################
SSHADD() {
  local keyfile="$1"
  echo "Добавляем ключ в ssh-agent: $keyfile"
  ssh-add "$keyfile"
}

SSHREM() {
  echo "Удаляем все ключи из ssh-agent..."
  ssh-add -D
}

##############################################################################
# 4. Изменение парольной фразы и комментария ключа
##############################################################################
change_passphrase() {
  local keyfile="$1"
  while true; do
    read -s -p "Новый пароль (Enter=пустой): " NP
    echo
    read -s -p "Подтвердите пароль: " CP
    echo
    if [[ "$NP" == "$CP" ]]; then
      ssh-keygen -p -f "$keyfile" -N "$NP"
      if [[ $? -eq 0 ]]; then
        echo "Пароль успешно изменён."
        SSHADD "$keyfile"
      else
        echo "Ошибка при изменении парольной фразы."
      fi
      return
    else
      echo "Пароли не совпадают, попробуйте снова."
    fi
  done
}

change_comment() {
  local keyfile="$1"
  read -p "Новый комментарий: " NCOMM
  if [[ -n "$NCOMM" ]]; then
    ssh-keygen -c -f "$keyfile" -C "$NCOMM"
    if [[ $? -eq 0 ]]; then
      echo "Комментарий успешно изменён."
      SSHADD "$keyfile"
    else
      echo "Ошибка при изменении комментария."
    fi
  else
    echo "Пустой комментарий, ничего не меняем."
  fi
  exit 0
}

##############################################################################
# 5. Создание нового ключа
##############################################################################
create_key() {
  local keyfile="$1"
  local keytype="$2"
  echo "=== Создание нового ключа ==="
  read -p "Введите комментарий для ключа (по умолчанию 'No Comment'): " COMMENT
  COMMENT=${COMMENT:-"No Comment"}
  echo "Введите парольную фразу (Enter=пустая):"
  read -s PASSPHRASE
  echo
  read -s -p "Подтвердите парольную фразу: " CONF
  echo
  if [[ "$PASSPHRASE" != "$CONF" ]]; then
    echo "Парольные фразы не совпадают. Выходим."
    exit 1
  fi
  ssh-keygen -t "$keytype" -C "$COMMENT" -f "$keyfile" -N "$PASSPHRASE"
  if [[ $? -eq 0 ]]; then
    echo "Ключ успешно создан: $keyfile"
    SSHADD "$keyfile"
  else
    echo "Ошибка при создании ключа."
    exit 1
  fi
  
  read -p "Передать ключ на сервер? [y/N]: " RESP
  RESP=${RESP,,}
  if [[ "$RESP" == "y" ]]; then
    transfer_key "$keyfile"
  fi
}

##############################################################################
# 6. Передача ключа на сервер
#    Сначала пробуем ssh-copy-id с загруженными ключами. При ошибке "Too many
#    authentication failures" очищаем ssh-agent и повторяем. Если ключи не подходят,
#    стандартный ssh-copy-id запросит пароль.
##############################################################################
transfer_key() {
  local keyfile="$1"
  local pubfile="${keyfile}.pub"
  echo "=== Передача ключа на сервер ==="
  read -p "Введите логин на сервере: " REM_USER
  read -p "Введите IP или hostname сервера: " REM_HOST
  read -p "Введите порт (по умолчанию 22): " REM_PORT
  REM_PORT=${REM_PORT:-22}

  echo "Пробуем передать ключ (ssh-copy-id) по ключам..."
  local output
  output="$(ssh-copy-id -i "$keyfile" -p "$REM_PORT" "${REM_USER}@${REM_HOST}" 2>&1)"
  local status=$?
  if [[ $status -eq 0 ]]; then
    echo "$output"
    final_server_setup "$keyfile" "$REM_USER" "$REM_HOST" "$REM_PORT"
    return
  fi

  echo "$output"
  if echo "$output" | grep -q "Too many authentication failures"; then
    echo "Обнаружено 'Too many authentication failures'. Очищаем ssh-agent..."
    SSHREM
    echo "Пробуем ещё раз с ssh-copy-id..."
    output="$(ssh-copy-id -i "$keyfile" -p "$REM_PORT" "${REM_USER}@${REM_HOST}" 2>&1)"
    status=$?
    if [[ $status -eq 0 ]]; then
      echo "$output"
      final_server_setup "$keyfile" "$REM_USER" "$REM_HOST" "$REM_PORT"
      return
    fi
    echo "$output"
    echo "Вторая попытка не удалась."
  else
    echo "Передача ключа по ключам не удалась (ключи не подошли или другая ошибка)."
  fi

  echo "Пожалуйста, введите пароль вручную, когда ssh-copy-id запросит его."
  output="$(ssh-copy-id -i "$keyfile" -p "$REM_PORT" "${REM_USER}@${REM_HOST}")"
  status=$?
  if [[ $status -eq 0 ]]; then
    echo "$output"
    final_server_setup "$keyfile" "$REM_USER" "$REM_HOST" "$REM_PORT"
    return
  else
    echo "ssh-copy-id не сработал."
    echo "Пробуем fallback с использованием команды cat."
    ssh "${REM_USER}@${REM_HOST}" -p "$REM_PORT" <<EOF
mkdir -p ~/.ssh
chmod 700 ~/.ssh
EOF
    ssh "${REM_USER}@${REM_HOST}" -p "$REM_PORT" "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$pubfile"
    if [[ $? -eq 0 ]]; then
      echo "Ключ успешно передан через fallback (cat)."
      final_server_setup "$keyfile" "$REM_USER" "$REM_HOST" "$REM_PORT"
      return
    else
      echo "Передача ключа не удалась."
      exit 1
    fi
  fi
}

##############################################################################
# 7. Финальная настройка входа по паролю на сервере
#    Сначала выводим текущее состояние параметра PasswordAuthentication, затем
#    локально запрашиваем у пользователя действие (включить или отключить),
#    и отправляем соответствующую команду через SSH.
##############################################################################
final_server_setup() {
  local keyfile="$1"
  local rem_user="$2"
  local rem_host="$3"
  local rem_port="$4"

  echo
  echo "Получаем текущее состояние PasswordAuthentication на сервере..."
  local current
  if [[ "$rem_user" == "root" ]]; then
    current="$(ssh -tt -i "$keyfile" -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -p "$rem_port" "${rem_user}@${rem_host}" "sshd -T 2>/dev/null | grep '^passwordauthentication'")"
  else
    # Для не-root пользователя запрашиваем sudo-пароль один раз
    read -s -p "Введите sudo пароль для ${rem_user} на сервере для получения статуса: " SUDOPASS
    echo
    current="$(ssh -tt -i "$keyfile" -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -p "$rem_port" "${rem_user}@${rem_host}" "echo \"$SUDOPASS\" | sudo -S sshd -T 2>/dev/null | grep '^passwordauthentication'")"
  fi
  echo "Текущее состояние: $current"
  
  read -p "Выберите действие: 1) Включить вход по паролю, 2) Отключить вход по паролю: " ACTION
  case "$ACTION" in
    1) NEW_STATE="yes" ;;
    2) NEW_STATE="no" ;;
    *) echo "Некорректный выбор."; exit 1 ;;
  esac

  local CMD
  if [[ "$rem_user" == "root" ]]; then
    CMD="sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config;
echo 'PasswordAuthentication $NEW_STATE' >> /etc/ssh/sshd_config;
if command -v systemctl >/dev/null 2>&1; then systemctl restart ssh || systemctl restart sshd; else service ssh restart || service sshd restart; fi"
  else
    # Для не-root: отправляем каждую команду отдельно с sudo и передачей пароля
    CMD1="echo \"$SUDOPASS\" | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config"
    CMD2="echo \"$SUDOPASS\" | sudo -S bash -c 'echo \"PasswordAuthentication $NEW_STATE\" >> /etc/ssh/sshd_config'"
    CMD3="echo \"$SUDOPASS\" | sudo -S bash -c 'if command -v systemctl >/dev/null 2>&1; then sudo systemctl restart ssh || sudo systemctl restart sshd; else sudo service ssh restart || sudo service sshd restart; fi'"
    CMD="$CMD1; $CMD2; $CMD3"
  fi

  echo "Выполняем команду на сервере для изменения настроек входа по паролю..."
  ssh -tt -i "$keyfile" -o IdentitiesOnly=yes -p "$rem_port" "${rem_user}@${rem_host}" "$CMD"
  if [[ $? -eq 0 ]]; then
    echo "Настройка входа по паролю успешно завершена."
  else
    echo "Ошибка при настройке входа по паролю."
  fi
}

##############################################################################
# 8. Функция: Интерактивная сессия (только по ключу) для настройки входа по паролю
##############################################################################
interactive_session_keyonly() {
  local keyfile="$1"
  local user="$2"
  local host="$3"
  local port="$4"

  echo "Подготавливаем ssh-agent: очищаем и добавляем ключ..."
  SSHREM
  SSHADD "$keyfile"

  echo "Открываем интерактивную SSH-сессию (только по ключу) на $user@$host (порт $port) с принудительным tty..."
  ssh -tt -i "$keyfile" -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -p "$port" "$user@$host"
  local st=$?
  echo "Интерактивная сессия завершена (код выхода: $st)."
}

##############################################################################
# 9. Главное меню
##############################################################################
main_menu() {
  echo "=== Главное меню ==="
  echo "Выберите тип ключа:"
  echo "1) RSA"
  echo "2) ED25519 (по умолчанию)"
  read -p "Ваш выбор (1-2): " KEY_TYPE_CHOICE
  case "$KEY_TYPE_CHOICE" in
    1) KEY_TYPE="rsa" ;;
    2|"") KEY_TYPE="ed25519" ;;
    *) echo "Некорректный выбор."; exit 1 ;;
  esac

  read -p "Введите имя файла ключа (по умолчанию ~/.ssh/id_${KEY_TYPE}): " KEY_NAME
  KEY_NAME=${KEY_NAME:-~/.ssh/id_${KEY_TYPE}}
  if [[ "$KEY_NAME" != /* && "$KEY_NAME" != ~/.ssh/* ]]; then
    KEY_NAME=~/.ssh/$KEY_NAME
  fi

  if [[ -f "$KEY_NAME" ]]; then
    local REAL_TYPE
    REAL_TYPE="$(ssh-keygen -lf "${KEY_NAME}.pub" 2>/dev/null | awk '{print $4}')"
    REAL_TYPE=${REAL_TYPE:-"unknown"}
    echo "Ключ $KEY_NAME ($REAL_TYPE) уже существует."
    echo "1) Ввести другое имя"
    echo "2) Отменить"
    echo "3) Перезаписать (создать заново)"
    echo "4) Изменить парольную фразу"
    echo "5) Изменить комментарий"
    echo "6) Передать ключ на сервер"
    echo "7) Добавить ключ в ssh-agent"
    echo "8) Убрать все ключи из ssh-agent"
    read -p "Ваш выбор: " CH
    case "$CH" in
      1) main_menu ;;
      2) echo "Выход."; exit 0 ;;
      3) create_key "$KEY_NAME" "$KEY_TYPE" ;;
      4) change_passphrase "$KEY_NAME" ;;
      5) change_comment "$KEY_NAME" ;;
      6) transfer_key "$KEY_NAME" ;;
      7) SSHADD "$KEY_NAME"; exit 0 ;;
      8) SSHREM; exit 0 ;;
      *) echo "Неправильный выбор."; exit 1 ;;
    esac
  else
    create_key "$KEY_NAME" "$KEY_TYPE"
  fi
}

##############################################################################
# 10. Старт скрипта: Проверка SSH, папки и запуск главного меню
##############################################################################
check_ssh_and_install
ensure_ssh_folder
main_menu

echo
echo "Скрипт завершён."
