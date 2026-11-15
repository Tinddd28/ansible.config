3x-ui
=====

Устанавливает панель [3x-ui](https://github.com/MHSanaei/3x-ui) официальным `install.sh`
в неинтерактивном режиме (`XUI_NONINTERACTIVE=1`).

- `install.sh` запускается только при первой установке или смене `xui_version`
  (скрипт каждый раз переустанавливает бинарники, настройки и база сохраняются).
- SSL у панели выключен, она слушает `127.0.0.1:{{ xui_panel_port }}` — доступ через ssh-туннель:
  `ssh -N -L 2053:127.0.0.1:2053 tunnel@<host>`.
- listenIP / порт / базовый путь проверяются при каждом запуске и выравниваются через `x-ui setting`.
- Логин и пароль задаются только при установке (`XUI_USERNAME` / `XUI_PASSWORD` из `.env`),
  пустые — генерируются, выводятся в конце плейбука и остаются в `/etc/x-ui/install-result.env`.

- База: `xui_db_type: sqlite | postgres` (только при первой установке). Для postgres без
  `XUI_DB_DSN` install.sh ставит PostgreSQL локально; параметры подключения в `/etc/default/x-ui`,
  роль подгружает их для `x-ui setting`.

Переменные — в `defaults/main.yml`.

    ansible-playbook playbooks/3x-ui.yml --limit <host>
