#!/bin/bash

##############################################################################
#  Скрипт для macOS (как клиента) для генерации SSH-ключей и их загрузки
#  на удалённый сервер (Linux). Включает управление PasswordAuthentication
#  на удалённом сервере (через sudo sed -i / systemctl / service).
#
#  Если на macOS нет ssh или ssh-copy-id, скрипт попробует помочь 
#  с установкой (через Homebrew). 
##############################################################################

# Проверка наличия ssh
if ! command -v ssh >/dev/null 2>&1; then
  echo "Команда 'ssh' не найдена в вашей macOS."
  echo "Установите пакет openssh (например: brew install openssh) и запустите скрипт снова."
  exit 1
fi

# Проверка наличия ssh-copy-id (бывает, что на macOS его нет)
if ! command -v ssh-copy-id >/dev/null 2>&1; then
  echo "Команда 'ssh-copy-id' не найдена."
  # Попробуем установить через Homebrew (если он установлен)
  if command -v brew >/dev/null 2>&1; then
    echo "Пробуем установить 'ssh-copy-id' через Homebrew..."
    brew install ssh-copy-id
    if ! command -v ssh-copy-id >/dev/null 2>&1; then
      echo "Не удалось установить ssh-copy-id через brew."
      echo "Придётся установить вручную или скопировать скрипт ssh-copy-id."
      echo "Инструкция: https://formulae.brew.sh/formula/ssh-copy-id"
      exit 1
    fi
  else
    echo "Homebrew не установлен, а ssh-copy-id отсутствует."
    echo "Установите Homebrew (https://brew.sh/) или ssh-copy-id вручную."
    exit 1
  fi
fi

# Убедимся, что скрипт выполняется не от root
if [ "$EUID" -eq 0 ]; then
  echo "Пожалуйста, запустите этот скрипт НЕ от имени root."
  exit 1
fi

echo "Выберите тип ключа:"
echo "1) RSA"
echo "2) ED25519 (по умолчанию)"
read -p "Ваш выбор (1-2): " KEY_TYPE_CHOICE
case "$KEY_TYPE_CHOICE" in
  1)  KEY_TYPE="rsa" ;;
  2|"")  KEY_TYPE="ed25519" ;;
  *)
    echo "Некорректный выбор. Завершение."
    exit 1
    ;;
esac

# Запрашиваем имя файла ключа
read -p "Введите имя файла для ключа (по умолчанию ~/.ssh/id_${KEY_TYPE}): " KEY_NAME
KEY_NAME=${KEY_NAME:-~/.ssh/id_${KEY_TYPE}}

# Убедимся, что ключ создаётся в .ssh
if [[ "$KEY_NAME" != /* && "$KEY_NAME" != ~/.ssh/* ]]; then
  KEY_NAME=~/.ssh/$KEY_NAME
fi

# Если файл ключа уже существует
if [ -f "$KEY_NAME" ]; then
  # Пытаемся определить тип по публичному ключу
  REAL_TYPE=$(ssh-keygen -lf "${KEY_NAME}.pub" 2>/dev/null | awk '{print $4}')
  # Если не вышло (нет .pub?), подставим "unknown"
  REAL_TYPE=${REAL_TYPE:-"unknown"}

  echo "Ключ с именем $KEY_NAME ($REAL_TYPE) уже существует."
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
      # Запустить заново
      exec "$0"
      ;;
    2)
      echo "Отмена создания ключа."
      exit 1
      ;;
    3)
      echo "Ключ будет перезаписан при генерации."
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
        # -c позволяет сменить комментарий
        ssh-keygen -c -f "$KEY_NAME" -C "$NEW_COMMENT"
        if [ $? -eq 0 ]; then
          echo "Комментарий успешно изменён."
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

      echo "ssh-copy-id -i \"$KEY_NAME\" -p \"$REMOTE_PORT\" \"${REMOTE_USER}@${REMOTE_IP}\""
      ssh-copy-id -i "$KEY_NAME" -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}"
      if [ $? -eq 0 ]; then
        echo "Ключ успешно передан."
      else
        echo "ssh-copy-id не сработал. Пробуем альтернативный метод."
        cat "${KEY_NAME}.pub" | ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
          "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
          echo "Ключ успешно передан альтернативным способом."
        else
          echo "Ошибка передачи ключа (оба способа)."
          exit 1
        fi
      fi

      # Предлагаем управлять PasswordAuthentication на удалённом сервере
      read -p "Управлять настройками входа по паролю? [y/N]: " CHANGE_PASSAUTH
      CHANGE_PASSAUTH=${CHANGE_PASSAUTH,,}
      if [[ "$CHANGE_PASSAUTH" == "y" ]]; then
        while true; do
          echo "Введите пароль sudo на удалённом сервере:"
          read -s SUDO_PASS

          ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_IP}" \
            "echo \"$SUDO_PASS\" | sudo -S -v" 2>/dev/null
          if [ $? -eq 0 ]; then
            echo "sudo-пароль принят."
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
      echo "Добавляем ключ в ssh-agent..."
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

# --- Если дошли сюда, значит создаём новый ключ ---

read -p "Введите комментарий для ключа (например, email или описание): " COMMENT
COMMENT=${COMMENT:-"No Comment"}

echo "Введите пароль для ключа (Enter, чтобы оставить без пароля):"
read -s PASSPHRASE
echo
echo "Подтвердите пароль (Enter для пустого):"
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

# --- Предлагаем сразу передать ключ на сервер ---
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

  # --- Предлагаем управлять PasswordAuthentication ---
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

echo "Ваш публичный ключ:"
cat "${KEY_NAME}.pub"

echo "Готово! Скрипт отработал на macOS, ключи созданы/переданы на сервер."
