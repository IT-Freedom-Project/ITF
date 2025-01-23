<#
.SYNOPSIS
  Пример скрипта для PowerShell в Windows, повторяющего логику bash-версии:
   - Создание/изменение SSH-ключей (RSA/ED25519)
   - Передача ключей на сервер (ssh-copy-id аналог)
   - Настройка PasswordAuthentication на удалённом сервере
#>

Write-Host ""
Write-Host "PowerShell-скрипт для управления SSH-ключами и настройкой входа по паролю"
Write-Host "(адаптирован из bash-скрипта IT Freedom Project v1.2)"
Write-Host ""

# --- 1) Проверка наличия ssh.exe ---

Function Check-SSH {
    Write-Host "Проверяем, установлен ли ssh..."
    $sshPath = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if ($null -eq $sshPath) {
        Write-Host "ssh.exe не найден. Установите OpenSSH Client в Windows."
        Write-Host "Например, через 'Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0'"
        Write-Host "Либо скачайте вручную."
        Exit 1
    } else {
        Write-Host "ssh.exe найден: $($sshPath.Source)"
    }
}

# --- 2) Проверка/создание папки ~/.ssh (в Windows: $env:USERPROFILE\.ssh) ---

Function Ensure-SSHFolder {
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (!(Test-Path $sshDir)) {
        Write-Host "Папка $sshDir не найдена. Создаём..."
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }
    # chmod 700 эквивалент в Windows не совсем нужен, можно задать ACL
    # Но для упрощения можно пропустить или задать (Windows не использует POSIX-права)
}

# --- 3) SSHADD / SSHREM ---

Function SSHADD($KeyFile) {
    Write-Host "Добавляем ключ в ssh-agent: $KeyFile"
    & ssh-add $KeyFile
}
Function SSHREM {
    Write-Host "Удаляем все ключи из ssh-agent..."
    & ssh-add -D
}

# --- 4) Изменение парольной фразы и комментария ключа ---

Function Change-Passphrase($KeyFile) {
    while ($true) {
        $NP = Read-Host "Новый пароль (Enter=пустой)" -AsSecureString
        Write-Host ""
        $CP = Read-Host "Подтвердите пароль (Enter=пустой)" -AsSecureString
        Write-Host ""
        # Сравним их как обычные строки:
        $nPlain = ConvertFrom-SecureString $NP
        $cPlain = ConvertFrom-SecureString $CP
        if ($nPlain -eq $cPlain) {
            # ssh-keygen -p -f "$KeyFile" -N "$NP"
            # PowerShell не интерполирует тут, нужно сделать cmd /c ...
            # Но SecureString complicates pass usage. Simpler approach: convert to plaintext carefully:
            $plainPass = (New-Object System.Net.NetworkCredential("", $NP)).Password
            & ssh-keygen -p -f $KeyFile -N $plainPass
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Пароль успешно изменён."
                SSHADD $KeyFile
            } else {
                Write-Host "Ошибка при изменении парольной фразы."
            }
            return
        } else {
            Write-Host "Пароли не совпадают, попробуйте снова."
        }
    }
}

Function Change-Comment($KeyFile) {
    $NCOMM = Read-Host "Новый комментарий"
    if (![string]::IsNullOrEmpty($NCOMM)) {
        & ssh-keygen -c -f $KeyFile -C $NCOMM
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Комментарий успешно изменён."
            SSHADD $KeyFile
        } else {
            Write-Host "Ошибка при изменении комментария."
        }
    } else {
        Write-Host "Пустой комментарий, ничего не меняем."
    }
    Exit 0
}

# --- 5) Создание нового ключа ---

Function Create-Key($KeyFile, $KeyType) {
    Write-Host "=== Создание нового ключа ==="
    $COMMENT = Read-Host "Введите комментарий для ключа (по умолчанию 'No Comment')"
    if ([string]::IsNullOrEmpty($COMMENT)) { $COMMENT = "No Comment" }
    $PASSPHRASE = Read-Host "Введите парольную фразу (Enter=пустая)" -AsSecureString
    $CONF = Read-Host "Подтвердите парольную фразу (Enter=пустая)" -AsSecureString
    if ( (ConvertFrom-SecureString $PASSPHRASE) -ne (ConvertFrom-SecureString $CONF) ) {
        Write-Host "Парольные фразы не совпадают. Выходим."
        Exit 1
    }
    $plainPass = (New-Object System.Net.NetworkCredential("", $PASSPHRASE)).Password
    & ssh-keygen -t $KeyType -C $COMMENT -f $KeyFile -N $plainPass
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ключ успешно создан: $KeyFile"
        SSHADD $KeyFile
    } else {
        Write-Host "Ошибка при создании ключа."
        Exit 1
    }

    $RESP = Read-Host "Передать ключ на сервер? [y/N]"
    $RESP = $RESP.ToLower()
    if ($RESP -eq "y") {
        Transfer-Key $KeyFile
    }
}

# --- 6) Передача ключа на сервер ---

Function Transfer-Key($KeyFile) {
    Write-Host "=== Передача ключа на сервер ==="
    $REM_USER = Read-Host "Введите логин на сервере"
    $REM_HOST = Read-Host "Введите IP или hostname сервера"
    $PortIn = Read-Host "Введите порт (по умолчанию 22)"
    if ([string]::IsNullOrEmpty($PortIn)) { $PortIn = "22" }

    Write-Host "Пробуем передать ключ (ssh-copy-id) по ключам..."
    # В Windows нет ssh-copy-id по умолчанию. Можно написать свою реализацию.
    # simplest approach: emulate some logic
    # or ask user to install 'ssh-copy-id' under Windows environment, e.g. GitBash

    Write-Host "В Windows обычно нет ssh-copy-id. Fallback: вручную cat .pub -> authorized_keys"
    # minimal approach: 
    & ssh -p $PortIn "$REM_USER@$REM_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh" 
    & type "$KeyFile.pub" | ssh -p $PortIn "$REM_USER@$REM_HOST" "cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ключ успешно передан (fallback)."
        Final-Server-Setup $KeyFile $REM_USER $REM_HOST $PortIn
    } else {
        Write-Host "Ошибка при передаче ключа (fallback)."
        Exit 1
    }
}

# --- 7) Финальная настройка входа по паролю ---

Function Final-Server-Setup($KeyFile, $User, $Host, $Port) {
    Write-Host "`n=== Настройка входа по паролю ==="
    Write-Host "Добавляем наш ключ в ssh-agent (если не добавлен)."
    SSHADD $KeyFile

    Write-Host "Получаем текущее состояние PasswordAuthentication на сервере, используя -i $KeyFile..."

    if ($User -eq "root") {
        $current = & ssh -tt -i $KeyFile -p $Port "$User@$Host" "sshd -T 2>/dev/null | grep '^passwordauthentication'"
    }
    else {
        $SUDOPASS = Read-Host "Введите sudo пароль для $User на сервере (получение статуса)" -AsSecureString
        $SudoPlain = (New-Object System.Net.NetworkCredential("", $SUDOPASS)).Password
        $current = & ssh -tt -i $KeyFile -p $Port "$User@$Host" "echo \"$SudoPlain\" | sudo -S sshd -T 2>/dev/null | grep '^passwordauthentication'"
    }

    $state = ""
    if (![string]::IsNullOrEmpty($current)) {
        if ($current -match "yes") {
            $state = "yes"
            Write-Host "Вход по паролю сейчас ВКЛЮЧЁН (yes)."
        } elseif ($current -match "no") {
            $state = "no"
            Write-Host "Вход по паролю сейчас ОТКЛЮЧЁН (no)."
        } else {
            Write-Host "Не удалось определить (неизвестный ответ: $current)"
        }
    } else {
        Write-Host "Не удалось получить данные (пустой ответ)."
    }

    while ($true) {
        Write-Host ""
        switch ($state) {
            "yes" {
                Write-Host "1) Ничего не менять"
                Write-Host "2) ОТКЛЮЧИТЬ вход по паролю"
            }
            "no" {
                Write-Host "1) Ничего не менять"
                Write-Host "2) ВКЛЮЧИТЬ вход по паролю"
            }
            default {
                Write-Host "1) Ничего не менять"
                Write-Host "2) ВКЛЮЧИТЬ вход по паролю (по умолчанию)"
            }
        }
        $CHOICE = Read-Host "Ваш выбор (1-2)"
        if ($CHOICE -eq "1") {
            Write-Host "Оставляем без изменений."
            return
        } elseif ($CHOICE -eq "2") {
            if ($state -eq "yes") { $NEW_STATE = "no" }
            else { $NEW_STATE = "yes" }
            break
        } else {
            Write-Host "Некорректный выбор. Повторите."
        }
    }

    $CMD = ""
    if ($User -eq "root") {
        $CMD = @"
sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
echo 'PasswordAuthentication $NEW_STATE' >> /etc/ssh/sshd_config
if command -v systemctl >/dev/null 2>&1; then systemctl restart ssh || systemctl restart sshd; else service ssh restart || service sshd restart; fi
"@
    } else {
        $SUDOPASS = Read-Host "Введите sudo пароль для $User (для внесения настроек)" -AsSecureString
        $SudoPlain2 = (New-Object System.Net.NetworkCredential("", $SUDOPASS)).Password

        $CMD = @"
echo '$SudoPlain2' | sudo -S sed -i '/^[#[:space:]]*PasswordAuthentication/d' /etc/ssh/sshd_config
echo '$SudoPlain2' | sudo -S bash -c 'echo ""PasswordAuthentication $NEW_STATE"" >> /etc/ssh/sshd_config'
echo '$SudoPlain2' | sudo -S bash -c 'if command -v systemctl >/dev/null 2>&1; then systemctl restart ssh || systemctl restart sshd; else service ssh restart || service sshd restart; fi'
"@
    }

    Write-Host "Изменяем PasswordAuthentication -> $NEW_STATE"
    & ssh -tt -i $KeyFile -p $Port "$User@$Host" $CMD
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Настройка входа по паролю успешно изменена."
    } else {
        Write-Host "Ошибка при настройке входа по паролю."
    }
}

# --- 8) Интерактивная сессия (только по ключу) ---

Function Interactive-SessionKeyOnly($KeyFile, $User, $Host, $Port) {
    Write-Host "Подготавливаем ssh-agent: очищаем и добавляем ключ..."
    SSHREM
    SSHADD $KeyFile

    Write-Host "Открываем интерактивную SSH-сессию (только по ключу) на $User@$Host (port $Port)."
    & ssh -tt -i $KeyFile -p $Port "$User@$Host"
    Write-Host "Интерактивная сессия завершена."
}

# --- 9) Главное меню ---
Function Main-Menu {
    while ($true) {
        Write-Host "`n=== Главное меню ==="
        Write-Host "Выберите тип ключа:"
        Write-Host "1) RSA"
        Write-Host "2) ED25519 (по умолчанию)"
        Write-Host "3) Выход из скрипта"
        $KEY_TYPE_CHOICE = Read-Host "Ваш выбор (1-3)"

        switch ($KEY_TYPE_CHOICE) {
            "1" { $KEY_TYPE = "rsa" }
            "2" { $KEY_TYPE = "ed25519" }
            ""  { $KEY_TYPE = "ed25519" }
            "3" { Write-Host "Выходим."; return }
            default {
                Write-Host "Некорректный выбор. Повторите."
                continue
            }
        }

        $KeyNameIn = Read-Host "Введите имя файла ключа (по умолчанию %USERPROFILE%\\.ssh\\id_$KEY_TYPE)"
        if ([string]::IsNullOrEmpty($KeyNameIn)) {
            $KeyNameIn = "$env:USERPROFILE\.ssh\id_$KEY_TYPE"
        }
        else {
            # если пользователь ввёл относительный путь, prepend %USERPROFILE%\.ssh ?
            if ($KeyNameIn -notmatch '^[A-Za-z]?:?\\') {
                # Не абсолютный. Добавим .ssh
                $KeyNameIn = "$env:USERPROFILE\.ssh\$KeyNameIn"
            }
        }

        if (Test-Path $KeyNameIn) {
            # Ключ существует
            $PubPath = $KeyNameIn + ".pub"
            $typeOut = & ssh-keygen -lf $PubPath 2>$null
            if ($LASTEXITCODE -eq 0 -and $typeOut) {
                $parts = $typeOut.Split(" ")
                $RealType = if ($parts.Count -ge 4) { $parts[3] } else { "unknown" }
                Write-Host "Ключ $KeyNameIn ($RealType) уже существует."
            }
            else {
                Write-Host "Ключ $KeyNameIn уже существует, тип неизвестен."
            }
            while ($true) {
                Write-Host "1) Ввести другое имя"
                Write-Host "2) Отменить"
                Write-Host "3) Перезаписать (создать заново)"
                Write-Host "4) Изменить парольную фразу"
                Write-Host "5) Изменить комментарий"
                Write-Host "6) Передать ключ на сервер"
                Write-Host "7) Добавить ключ в ssh-agent"
                Write-Host "8) Убрать все ключи из ssh-agent"
                Write-Host "9) Назад в главное меню"
                $ch2 = Read-Host "Ваш выбор"
                switch ($ch2) {
                    "1" { break } # вернёмся к началу, user выберет имя
                    "2" { Write-Host "Выход."; return }
                    "3" { Create-Key $KeyNameIn $KEY_TYPE; break }
                    "4" { Change-Passphrase $KeyNameIn; break }
                    "5" { Change-Comment $KeyNameIn; break }
                    "6" { Transfer-Key $KeyNameIn; break }
                    "7" { SSHADD $KeyNameIn }
                    "8" { SSHREM }
                    "9" { break }
                    default {
                        Write-Host "Неправильный выбор. Повторите."
                    }
                }
            }
        }
        else {
            Create-Key $KeyNameIn $KEY_TYPE
        }
    }
}

# --- Старт ---

Check-SSH
Ensure-SSHFolder
Main-Menu

Write-Host "`nСкрипт завершён."
