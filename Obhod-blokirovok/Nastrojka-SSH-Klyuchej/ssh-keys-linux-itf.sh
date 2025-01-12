#!/bin/bash

##############################################################################
# Универсальный скрипт для Debian/Ubuntu и CentOS/RHEL/Fedora.
# 1. Проверяет, что скрипт не запущен от root.
# 2. Проверяет, установлен ли 'ssh'. Если нет — пытается установить через
#    apt-get (Debian/Ubuntu) или dnf/yum (CentOS/RHEL/Fedora).
# 3. Создаёт/управляет SSH-ключами (без вопроса "Хотите ли вы пароль?"; 
#    просто предлагает ввести — пустая строка = без пароля).
# 4. "ssh-copy-id" или альтернативный метод (через cat >> authorized_keys).
# 5. Настраивает "PasswordAuthentication" на удалённом сервере (если нужно).
##############################################################################

######################
# 1. Защита от запуска скрипта от root
######################
if [ "$EUID" -eq 0 ]; then
  echo "Пожалуйста, запустите этот скрипт НЕ от имени root."
  exit 1
fi

######################
# 2. Проверяем, есть ли 'ssh'. Если нет, пытаемся установить.
######################
if ! command -v ssh >/dev/null 2>&1; then
  echo "Команда 'ssh' не найдена. Попробуем установить..."

  # Определяем, какой пакетный менеджер у нас есть
  if command -v apt-get >/dev/null 2>&1; then
    # Для Debian/Ubuntu
    echo "Обнаружен apt-get. Ставим 'openssh-client'..."
    sudo apt-get update && sudo apt-get install -y openssh-client
  elif command -v dnf >/dev/null 2>&1; then
    # Для Fedora, RHEL 8+, CentOS 8+
    echo "Обнаружен dnf. Ставим 'openssh-clients'..."
    sudo dnf install -y openssh-clients
  elif command -v yum >/dev/null 2>&1; then
    # Для RHEL/CentOS 7 и старее
    echo "Обнаружен yum. Ставим 'openssh-clients'..."
    sudo yum install -y openssh-clients
  else
    echo "Не удалось обнаружить пакетный менеджер (apt-get/dnf/yum)."
    echo "Установите 'ssh' (openssh-client) вручную и повторите."
    exit 1
  fi

  # Проверим, что установка прошла успешно
  if ! command -v ssh >/dev/null 2>&1; then
    echo "Не удалось установить 'ssh'. Завершение."
    exit 1
  fi
fi

##############################################################################
# 3. Основная логика управления ключами
##############################################################################

# Запрашиваем тип ключа
echo "Выберите тип ключа:"
echo "1) RSA"
echo "2) ED25519 (по умолчанию)"
read -p "Ваш выбор (1-2): " KEY_TYPE_CHOICE
case "$KEY_TYPE_CHOICE" in
  1)
    KEY_TYPE="rsa"
    ;;
  2|"")
    KEY_TYPE="ed25519"
    ;;
  *)
    echo "Некорректный выбор. Завершение."
    exit 1
    ;;
esac

if [[ "$KEY_TYPE" != "rsa" && "$KEY_TYPE" != "ed25519" ]]; then
  echo "Некорректный тип ключа. Завершение."
  exit 1
fi

# Запрашиваем имя файла ключа
read -p "Введите имя файла для ключа (по умолчанию ~/.ssh/id_${KEY_TYPE}): " KEY_NAME
KEY_NAME=${KEY_NAME:-~/.ssh/id_${KEY_TYPE}}

# Убедимся, что ключ создается в папке .ssh
if [[ "$KEY_NAME" != /* && "$KEY_NAME" != ~/.ssh/* ]]; then
  KEY_NAME=~/.ssh/$KEY_NAME
fi

###################
# 4. Проверяем, существует ли уже ключ
###################
if [ -f "$KEY_NAME" ]; then
  # Пытаемся определить тип по публичному ключу
  REAL_TYPE=$(ssh-keygen -lf "${KEY_NAME}.pub" 2>/dev/null | awk '{print $4}')
  # Если не вышло (нет .pub?), подставим "unknown"
  REAL_TYPE=${REAL_TYPE:-"unknown"}

  echo "Ключ с именем $KEY_NAME $REAL_TYPE уже существует."
  echo "Выберите действие:"
  echo "1) Ввести другое имя"
  echo "2) Отменить создание ключа"
  echo "3) Перезаписать существующий ключ"
  echo "4) Изменить пароль для существующего ключа"
  echo "5) Изменить комментарий для существующего ключа"
  echo "6) Передать ключ на сервер (всегда)"
  echo "7) Добавить ключ в ssh-agent"
  read -p "Ваш выбор (1-7): " CHOICE

  case "$CHOICE" in
    1)
      # Перезапустить скрипт заново
      exec "$0"
      ;;
    2)
      echo "Отмена создания ключа."
      exit 1
      ;;
    3)
      echo "Ключ будет перезаписан (при генерации)."
      ;;
    4)
      echo "Изменение пароля для существующего ключа."
      while true; do
        read -s -p "Введите новый пароль (Enter для пустого): " NEW_PASSPHRASE
        echo
        read -s -p "Подтвердите пароль (Enter для пустого): " CONFIRM_PASSPHRASE
        echo
        if [[ "$NEW_PASSPHRASE" == "$CONFIRM_PASSPHRASE" ]]; then
          ssh-keygen -p -f "$KEY_NAME" -N "$NEW_PASSPHRASE"
          if [ $? -eq 0 ]; then
            echo "Пароль для ключа успешно изменен."
            ssh-add "$KEY_NAME"
            echo "Ключ добавлен в ssh-agent."
          else
            echo "Ошибка при изменении пароля ключа."
          fi
          exit 0
        else
          echo "Пароли не совпадают. Повторите ввод."
        fi
      done
      ;;
    5)
      echo "Изменение комментария для существующего ключа."
      read -p "Введите новый комментарий: " NEW_COMMENT
      if [[ -n "$NEW_COMMENT" ]]; then
        ssh-keygen -c -f "$KEY_NAME" -C "$NEW_COMMENT"
        if [ $? -eq 0 ]; then
          echo "Комментарий для ключа успешно изменён."
          ssh-add "$KEY_NAME"
          echo "Ключ добавлен в ssh-agent."
        else
          echo "Ошибка при изменении комментария."
        fi
      else
        echo "Пустой комментарий, ничего не меняем."
      fi
      exit 0
      ;;
    6)
      # Передача уже существующего ключа
      echo "Передача ключа на сервер."
      read -p "Введите логин для сервера: " REMOTE_USER
      read -p "Введите IP-адрес сервера: " REMOTE_IP
      read -p "Введите порт сервера (по умолчанию 22): " REMOTE_PORT
      REMOTE_PORT=${REMOTE_PORT:-22}

      echo "Передача ключа на сервер (ssh-copy-id)..."
      ssh-copy-id -i "$KEY_NAME" -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}"
      if [ $? -eq 0 ]; then
        echo "Ключ успешно передан на сервер."
      else
        echo "Не удалось передать ключ через ssh-copy-id."
        echo "Пробуем альтернативный способ (cat >> authorized_keys)..."
        cat "${KEY_NAME}.pub" | ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
          "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
          echo "Ключ успешно передан альтернативным способом."
        else
          echo "Ошибка передачи ключа (оба способа)."
          exit 1
        fi
      fi

      # Предлагаем управлять настройками входа по паролю (PasswordAuthentication)
      read -p "Хотите ли вы управлять настройками входа по паролю на сервере? [y/N]: " CHANGE_PASSAUTH
      CHANGE_PASSAUTH=${CHANGE_PASSAUTH,,}
      if [[ "$CHANGE_PASSAUTH" == "y" ]]; then
        while true; do
          echo "Введите пароль sudo на сервере:"
          read -s SUDO_PASS

          ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
            "echo \"$SUDO_PASS\" | sudo -S -v" 2>/dev/null
          if [ $? -eq 0 ]; then
            echo "Пароль принят."
            break
          else
            echo "Неверный пароль sudo, попробуйте ещё раз."
          fi
        done

        # Проверяем текущее состояние
        CURRENT_PA=$(ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
          "echo \"$SUDO_PASS\" | sudo -S sshd -T | grep '^passwordauthentication'")
        if echo "$CURRENT_PA" | grep -iq 'yes'; then
          echo "Сейчас вход по паролю ВКЛЮЧЕН."
        else
          echo "Сейчас вход по паролю ОТКЛЮЧЕН."
        fi

        echo "Включить (y) или отключить (n) вход по паролю? [y/n]:"
        read -p "Ваш выбор: " TOGGLE
        TOGGLE=${TOGGLE,,}
        if [[ "$TOGGLE" == "y" ]]; then
          ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" "
            echo \"$SUDO_PASS\" | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
            echo \"$SUDO_PASS\" | sudo -S bash -c 'echo \"PasswordAuthentication yes\" >> /etc/ssh/sshd_config'
            if command -v systemctl >/dev/null 2>&1; then
              echo \"$SUDO_PASS\" | sudo -S systemctl restart ssh || sudo -S systemctl restart sshd
            else
              echo \"$SUDO_PASS\" | sudo -S service ssh restart || sudo -S service sshd restart
            fi
          "
          echo "Вход по паролю включен."
        elif [[ "$TOGGLE" == "n" ]]; then
          ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" "
            echo \"$SUDO_PASS\" | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
            echo \"$SUDO_PASS\" | sudo -S bash -c 'echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config'
            if command -v systemctl >/dev/null 2>&1; then
              echo \"$SUDO_PASS\" | sudo -S systemctl restart ssh || sudo -S systemctl restart sshd
            else
              echo \"$SUDO_PASS\" | sudo -S service ssh restart || sudo -S service sshd restart
            fi
          "
          echo "Вход по паролю отключен."
        else
          echo "Ничего не меняем."
        fi
      fi
      exit 0
      ;;
    7)
      echo "Добавляем ключ в ssh-agent."
      ssh-add "$KEY_NAME"
      if [ $? -eq 0 ]; then
        echo "Ключ добавлен в ssh-agent."
      else
        echo "Ошибка при добавлении."
      fi
      exit 0
      ;;
    *)
      echo "Некорректный выбор. Завершение."
      exit 1
      ;;
  esac
fi

######################
# Создаём НОВЫЙ ключ (если его не было или выбрано перезаписать)
######################
read -p "Введите описание для ключа (например, email): " COMMENT
COMMENT=${COMMENT:-"No Comment"}

echo "Введите пароль для ключа (Enter — без пароля):"
read -s PASSPHRASE
echo
echo "Подтвердите пароль (Enter — без пароля):"
read -s CONFIRM_PASSPHRASE
echo
if [[ "$PASSPHRASE" != "$CONFIRM_PASSPHRASE" ]]; then
  echo "Пароли не совпадают. Завершение."
  exit 1
fi

echo "Генерация ключа SSH..."
ssh-keygen -t "$KEY_TYPE" -C "$COMMENT" -f "$KEY_NAME" -N "$PASSPHRASE"
if [ $? -eq 0 ]; then
  echo "SSH-ключ успешно создан:"
  echo "  Приватный ключ: $KEY_NAME"
  echo "  Публичный ключ: ${KEY_NAME}.pub"
  ssh-add "$KEY_NAME"
  echo "Ключ добавлен в ssh-agent."
else
  echo "Ошибка при создании ключа."
  exit 1
fi

######################
# Предлагаем сразу передать ключ на сервер
######################
read -p "Хотите передать ключ на сервер? [y/N]: " TRANSFER_KEY
TRANSFER_KEY=${TRANSFER_KEY,,}
if [[ "$TRANSFER_KEY" == "y" ]]; then
  read -p "Введите логин для сервера: " REMOTE_USER
  read -p "Введите IP-адрес сервера: " REMOTE_IP
  read -p "Введите порт сервера (по умолчанию 22): " REMOTE_PORT
  REMOTE_PORT=${REMOTE_PORT:-22}

  echo "Передача ключа на сервер (ssh-copy-id)..."
  ssh-copy-id -i "$KEY_NAME" -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}"
  if [ $? -eq 0 ]; then
    echo "Ключ успешно передан."
  else
    echo "ssh-copy-id не сработал. Пробуем альтернативу..."
    cat "${KEY_NAME}.pub" | ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
      "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    if [ $? -eq 0 ]; then
      echo "Ключ успешно передан альтернативным способом."
    else
      echo "Ошибка передачи ключа (оба способа)."
      exit 1
    fi
  fi

  # Предлагаем управлять PasswordAuthentication
  read -p "Управлять настройками входа по паролю на сервере? [y/N]: " CHANGE_PASSAUTH
  CHANGE_PASSAUTH=${CHANGE_PASSAUTH,,}
  if [[ "$CHANGE_PASSAUTH" == "y" ]]; then
    while true; do
      echo "Введите sudo-пароль на сервере (для правки /etc/ssh/sshd_config):"
      read -s SUDO_PASS

      ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
        "echo \"$SUDO_PASS\" | sudo -S -v" 2>/dev/null
      if [ $? -eq 0 ]; then
        echo "Пароль принят."
        break
      else
        echo "Неверный пароль sudo, попробуйте ещё раз."
      fi
    done

    CURRENT_PA=$(ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
      "echo \"$SUDO_PASS\" | sudo -S sshd -T | grep '^passwordauthentication'")
    if echo "$CURRENT_PA" | grep -iq 'yes'; then
      echo "Сейчас вход по паролю ВКЛЮЧЕН."
    else
      echo "Сейчас вход по паролю ОТКЛЮЧЕН."
    fi

    echo "Включить (y) или отключить (n) вход по паролю? [y/n]:"
    read -p "Ваш выбор: " TOGGLE
    TOGGLE=${TOGGLE,,}
    if [[ "$TOGGLE" == "y" ]]; then
      ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" "
        echo \"$SUDO_PASS\" | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
        echo \"$SUDO_PASS\" | sudo -S bash -c 'echo \"PasswordAuthentication yes\" >> /etc/ssh/sshd_config'
        if command -v systemctl >/dev/null 2>&1; then
          echo \"$SUDO_PASS\" | sudo -S systemctl restart ssh || sudo -S systemctl restart sshd
        else
          echo \"$SUDO_PASS\" | sudo -S service ssh restart || sudo -S service sshd restart
        fi
      "
      echo "Вход по паролю включен."
    elif [[ "$TOGGLE" == "n" ]]; then
      ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" "
        echo \"$SUDO_PASS\" | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
        echo \"$SUDO_PASS\" | sudo -S bash -c 'echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config'
        if command -v systemctl >/dev/null 2>&1; then
          echo \"$SUDO_PASS\" | sudo -S systemctl restart ssh || sudo -S systemctl restart sshd
        else
          echo \"$SUDO_PASS\" | sudo -S service ssh restart || sudo -S service sshd restart
        fi
      "
      echo "Вход по паролю отключен."
    else
      echo "Ничего не меняем."
    fi
  fi
fi

echo
echo "Ваш публичный ключ:"
cat "${KEY_NAME}.pub"
echo
echo "Готово! Скрипт завершён. Используйте публичный ключ для авторизации."
