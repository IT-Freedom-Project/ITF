# Проксирование TCP трафика с помощью HAProxy
Сначала рекомендую настроить [безопасность сервера](https://github.com/IT-Freedom-Project/ITF/tree/main/nastrojka-servera/nastrojka-bezopasnosti), [вход по ключам](https://github.com/IT-Freedom-Project/ITF/tree/main/nastrojka-servera/nastrojka-ssh-klyuchej) и [накатить BBR](https://github.com/IT-Freedom-Project/ITF/tree/main/nastrojka-servera/nastrojka-bbr) для ускорения сети.

Не забудьте предварительно открыть 443 порт, если блокируете:
```sudo ufw allow 443/tcp```

На облачных хостингах порты могут открываться из личного кабинета через правила файервола

1. Обновляем систему:\
```sudo apt update``` \
```sudo apt upgrade -y```

2. Ставим  HAProxy:\
```sudo apt install -y haproxy```

3. Обнуляем конфиг по умолчанию:\
```sudo truncate -s 0 /etc/haproxy/haproxy.cfg```

4. Редактируем [конфиг](https://github.com/IT-Freedom-Project/ITF/blob/main/proksirovanie-trafika/proksirovanie-haproxy/haproxy.cfg), подставляя свои SNI в группах и IP своего конечного сервера вместо 100.150.200.250 и 101.151.201.251.
  
5. Открываем конфиг:\
   ```sudo nano /etc/haproxy/haproxy.cfg```
6. Копируем текст через Ctrl + Shift + V, сохраняем через Ctrl + O, потом Enter, потом Ctrl + X .
7. Проверяем валидность конфига:\
```sudo haproxy -c -f /etc/haproxy/haproxy.cfg```
8. Если всё ок, то мягко перезапускаем haproxy:\
   ```sudo systemctl restart haproxy```

