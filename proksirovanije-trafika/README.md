# Проксирование трафика через сервер РФ с помощью Haproxy (без установки панели)
Сначала рекомендую настроить безопасность сервера, вход по ключам и накатить BBR для ускорения сети.

1. Обновляем систему:\
```sudo apt update``` \
```sudo apt upgrade -y```

2. Ставим  HAProxy:\
```sudo apt install -y```

3. Обнуляем конфиг по умолчанию:\
```sudo truncate -s 0 /etc/haproxy/haproxy.cfg```

4. Редактируем [конфиг](https://github.com/IT-Freedom-Project/ITF/blob/main/proksirovanije-trafika/haproxy.cfg), подставляя IP своего зарубежного сервера вместо 100.150.200.250 и 101.151.201.251.
  
5. Открываем конфиг:\
   ```sudo nano /etc/haproxy/haproxy.cfg```
6. Копируем текст через ctrl + shift + v, сохраняем через ctl + o, потом enter, потом ctrl + x.
7. Проверяем валидность конфига:\
```sudo haproxy -c -f /etc/haproxy/haproxy.cfg```
8. Если всё ок, то мягко перезапускаем haproxy:\
   ```sudo systemctl restart haproxy```

