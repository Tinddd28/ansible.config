# ansible.config

Ansible-конфигурация VPS: панель **3x-ui** (xray, VLESS + REALITY), **caddy** с naive-прокси,
сайтом-заглушкой и публикацией панели/подписки, файрвол **ufw**, служебные пользователи и
(отдельно) MTProto-прокси **telemt**.

## Как устроен сервер

```
                  :443/tcp                         127.0.0.1:8443
клиент ──────► xray (инбаунд 3x-ui, REALITY) ──────► caddy (network_mode: host)
                │ свои REALITY-клиенты                ├─ naive (forward_proxy)
                │ обслуживаются здесь                 ├─ /<xui_web_base_path>/ → панель 127.0.0.1:<xui_panel_port>
                │                                     ├─ /<xui_sub_path>/      → подписка 127.0.0.1:2096
                └ всё остальное (браузеры, сканеры,   └─ остальное             → сайт-заглушка
                  naive, ACME TLS-ALPN) → target
         :80/tcp ─────────────────────────────────► caddy: 308 на https://<domain_name>, ACME HTTP-01
```

- Наружу открыты только ssh, 80 и 443 (роль `firewall`).
- Панель и подписка слушают `127.0.0.1` и снаружи доступны только через caddy или ssh-туннель.
- Сертификат домена получает caddy (Let's Encrypt через HTTP-01 на :80 или TLS-ALPN-01 через xray).
- Есть второй режим — **без caddy** (`xui_ssl_mode: ip`), см. [ниже](#режим-без-caddy-сертификат-на-ip).

## Что нужно установить

### На машине, откуда запускается ansible

| Что | Зачем |
|---|---|
| `ansible-core` 2.16+ (проверено на 2.22) | сам ansible |
| коллекции `community.docker`, `community.general`, `ansible.posix` | модули docker, ufw, authorized_key |
| Docker (демон, текущий пользователь в группе `docker`) | сборка образа caddy и выгрузка его на сервер |
| `make`, `sha256sum` (coreutils) | `make caddy` |
| ssh-ключ, который принимает `root` на серверах | подключение |

```sh
# Arch
sudo pacman -S ansible docker make
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"          # перелогиниться

# Debian/Ubuntu
sudo apt install ansible docker.io make

ansible-galaxy collection install community.docker community.general ansible.posix
```

buildx не нужен: Dockerfile собирается обычным `docker build`. Образ собирается под архитектуру
локальной машины — на amd64 получится образ для amd64-серверов (роль проверит совпадение).

### На серверах

- Ubuntu 22.04+ или Debian 12+ (используются apt, deb822-репозитории, `/etc/default/x-ui`).
- Вход `root` по ssh-ключу, `python3`.
- DNS: A-запись `domain_name` → IP сервера (для режима с caddy).
- Docker роль `docker` ставит сама из официального репозитория.

## Структура

```
ansible.cfg                inventory = hosts.yml,inventory.yml
hosts.yml(.example)        хосты и их переменные            (hosts.yml — в .gitignore)
inventory.yml(.example)    группы хостов                    (в .gitignore)
.env(.example)             общие секреты и версии           (в .gitignore)
group_vars/all/*.example   общие переопределения caddy/telemt
Makefile                   make caddy — сборка образа caddy-naive
docker/caddy/Dockerfile    caddy + forwardproxy (naive)
playbooks/
  caddy.yml                users → docker → caddy
  3x-ui.yml                3x-ui
  firewall.yml             ufw
  telemt-proxy.yml         users → docker → telemt
roles/
  users  docker  caddy  3x-ui  firewall  telemt-proxy
  caddy/files/<host>/      сайт-заглушка каждого хоста       (*-vps-* — в .gitignore)
```

## Настройка

### 1. Инвентарь и секреты

```sh
cp hosts.yml.example hosts.yml
cp inventory.yml.example inventory.yml
cp .env.example .env
```

`.env` — общее для всех серверов:

```sh
CADDY_VERSION=2.11.9                  # версия caddy, должна совпадать с собранным образом
NAIVE_USER=user                       # логин naive
NAIVE_PASSWORD=...                    # openssl rand -hex 16 (только [A-Za-z0-9._~-], 12+ символов)
XUI_USERNAME= / XUI_PASSWORD=         # логин панели при первой установке; пусто — сгенерируются
XUI_DB_DSN=                           # только для xui_db_type: postgres с внешним сервером
```

`hosts.yml` — у каждого сервера своё:

```yaml
all:
  vars:
    ansible_user: root
    ansible_python_interpreter: auto_silent
  hosts:
    pl-vps-01:
      ansible_host: 203.0.113.10
      ansible_port: 22
      domain_name: pl-01.example.com        # домен сервера (caddy, REALITY serverNames, подписка)
      xui_name: "🇵🇱 Poland"                 # название подписки и имя создаваемого инбаунда
      xui_panel_port: 2053                  # порт панели на 127.0.0.1
      xui_web_base_path: change-me-random   # путь панели: https://<domain_name>/<path>/
      xui_sub_path: change-me-sub           # путь подписки: https://<domain_name>/<path>/
      xui_db_type: sqlite                   # sqlite | postgres (только при первой установке)
      xui_is_node: true                     # нода главной панели: выпустить токен для неё
```

Пути генерируйте случайными: `openssl rand -hex 12`.

### 2. Сайт-заглушка для каждого хоста

Caddy отдаёт `roles/caddy/files/<inventory_hostname>/` (весь каталог: `index.html` и любые ресурсы).
Общего сайта нет намеренно — одинаковые страницы на разных серверах легко связать между собой.
Без каталога хоста роль остановится. Каталоги хостов в `.gitignore` — храните их копию отдельно.
`roles/caddy/files/default/` — запасная страница, роль её не выкладывает.

### 3. Основные переменные

| Переменная | Где | По умолчанию | Смысл |
|---|---|---|---|
| `domain_name` | хост | — | домен сервера |
| `caddy_port` | хост | `8443` | локальный порт caddy (target для REALITY) |
| `caddy_acme_email` | group_vars | `""` | email для Let's Encrypt |
| `xui_ssl_mode` | хост | `none` | `none` — за caddy; `ip` — без caddy, сертификат на IP |
| `xui_version` | роль | `v3.11.0` | версия 3x-ui; смена — переустановка с сохранением базы |
| `xui_reality_inbound` | хост | `true` | создать VLESS+TCP+REALITY на 443, если его нет, с первым клиентом |
| `xui_inbound_client_email` | хост | `<inventory_hostname>` | email первого клиента (уникальный в панели) |
| `xui_reality_target` | хост | `127.0.0.1:<caddy_port>` | куда REALITY отдаёт чужой трафик |
| `xui_reality_fingerprint` | роль | `randomized` | uTLS fingerprint для ссылок |
| `xui_node_token_scope` | хост | `node-sync` | `node-admin` — ещё и обновление ноды с главной |
| `firewall_allow_extra` | хост | `[]` | дополнительные порты, `[{port: 8443, proto: tcp}]` |

Полный список — в `roles/*/defaults/main.yml`.

## Запуск

Все команды — из корня репозитория.

```sh
# 0. собрать образ caddy-naive локально (один раз и после смены версии/Dockerfile)
make caddy                          # или: make caddy CADDY_VERSION=2.11.9

# 1. загрузить .env в окружение (в каждой новой сессии терминала)
set -a; . ./.env; set +a

# 2. caddy: пользователи, docker, образ, сайт, naive, редирект с 80
ansible-playbook playbooks/caddy.yml --limit pl-vps-01

# 3. 3x-ui: установка, панель на 127.0.0.1, подписка, инбаунд REALITY, токен ноды
ansible-playbook playbooks/3x-ui.yml --limit pl-vps-01

# 4. файрвол — последним, когда всё работает
ansible-playbook playbooks/firewall.yml --limit pl-vps-01
```

Без `--limit` плейбук идёт по всем хостам. Пробный прогон без изменений — `--check --diff`
(на новом сервере дальше установки docker он не пройдёт: docker там ещё нет).

### Что выводится после запуска

- **Первая установка 3x-ui** — команда ssh-туннеля, адрес панели, логин и пароль
  (они же остаются на сервере в `/etc/x-ui/install-result.env`).
- **`xui_is_node: true`** — один раз выводит параметры для **Nodes → Add** на главной панели:
  scheme `https`, address `<domain_name>`, port `443`, base path `/<xui_web_base_path>/`, API-токен.
  Токен показывается только при создании. Перевыпустить (старый перестанет работать):

  ```sh
  ansible-playbook playbooks/3x-ui.yml --limit pl-vps-01 -e xui_node_token_rotate=true
  ```

### Доступ к панели

- Через caddy: `https://<domain_name>/<xui_web_base_path>/`.
- Через ssh-туннель (роль caddy создаёт пользователя `tunnel` без пароля и shell, с ключами root):

  ```sh
  ssh -N -L 2053:127.0.0.1:2053 -p <ansible_port> tunnel@<ansible_host>
  # → http://127.0.0.1:2053/<xui_web_base_path>/
  ```

Подписка: `https://<domain_name>/<xui_sub_path>/<subId клиента>`. Ссылку первого клиента роль
выводит сразу после создания инбаунда.

## Повторный запуск

Роли идемпотентны, на работающем сервере ничего не теряется:

- **caddy** — перезаписывает Caddyfile, compose и сайт; сертификаты в `/opt/caddy/data` остаются.
  Образ перезаливается только при смене build-id (версия + хеш Dockerfile).
- **3x-ui** — `install.sh` запускается только при первой установке, смене `xui_version` или
  отсутствии сертификата в режиме `ip`; база `/etc/x-ui` сохраняется. Роль выравнивает только
  listen/порт/путь панели и поля подписки — изменённое в интерфейсе вернётся к значениям из
  `hosts.yml`. Существующий инбаунд на 443 не трогается (ключи и клиенты не меняются).
  Временный API-токен `ansible` в конце всегда отзывается.
- **firewall** — если правила ufw отличаются от нужных, они сбрасываются и задаются заново
  (открытое вручную закроется; на время сброса ufw на секунды выключается).

## Режим без caddy: сертификат на IP

Для сервера без домена: `install.sh` выпускает короткоживущий сертификат Let's Encrypt на IP
(acme.sh, ~6 дней, продление cron'ом через HTTP-01 на :80). Панель и подписка слушают все
интерфейсы по https, роль `firewall` открывает их порты.

```yaml
    xx-vps-01:
      ansible_host: 203.0.113.20
      xui_ssl_mode: ip
      xui_panel_port: 2053
      xui_web_base_path: change-me-random
      xui_sub_path: change-me-sub
      xui_reality_target: "www.example.com:443"    # чужой сайт с TLS 1.3 и h2
      xui_reality_server_names: [www.example.com]
```

```sh
ansible-playbook playbooks/3x-ui.yml --limit xx-vps-01
ansible-playbook playbooks/firewall.yml --limit xx-vps-01
```

Роль `caddy` на таком хосте не запускается (обоим нужен порт 80).
Перевод такой панели под caddy: убрать сертификаты в панели (панель и подписка),
`~/.acme.sh/acme.sh --remove -d <IP>; rm -rf /root/cert/ip`, убрать `xui_ssl_mode: ip`,
затем `caddy.yml` → `3x-ui.yml` → `firewall.yml`.

## Ноды и главная панель

Нода, добавленная на главную панель, получает инбаунды и клиентов **с главной** — они хранятся
в базе главной панели. Поэтому:

- инбаунды ноды правьте на главной (правки на самой ноде перезапишутся);
- при переустановке ноды поставьте ей `xui_reality_inbound: false` (главная сама вернёт свой
  инбаунд с прежними ключами), а на главной обновите токен ноды;
- перед переустановкой сохраните базу: `cp /etc/x-ui/x-ui.db ~/x-ui.db.bak`.

## telemt (MTProto)

```sh
cp group_vars/all/telemt.yml.example group_vars/all/telemt.yml   # telemt_users, telemt_tls_domain
ansible-playbook playbooks/telemt-proxy.yml --limit pl-vps-01
```

По умолчанию telemt публикует `8443` — тот же порт, что у caddy. На одном сервере с caddy задайте
хосту другой `telemt_port` и добавьте его в `firewall_allow_extra`.

## Частые проблемы

| Симптом | Причина и что делать |
|---|---|
| `порт 80 или 8443 занят не caddy` | на сервере другой сервис (часто telemt на 8443): смените `caddy_port` или `telemt_port` |
| `caddy не работает (рестарты: N)` | смотрите выведенный лог; обычно конфликт портов или ошибка в Caddyfile |
| `локальный образ ... отсутствует или собран не из текущего Dockerfile` | `make caddy CADDY_VERSION=<версия из .env>` |
| `у панели настроен сертификат ..., а xui_ssl_mode=none` | панель ставилась вручную с TLS: уберите сертификат в панели или задайте `xui_ssl_mode: ip` |
| `сертификат Let's Encrypt на <IP> не выпущен` | порт 80 занят или закрыт; лог `/root/.acme.sh/acme.sh.log` |
| `API-токен "ansible" не отозван` | панель не ответила в конце прогона; удалите токен в Settings → API Tokens или он отзовётся при следующем запуске |
| `панель установлена с базой ..., а xui_db_type=...` | смена sqlite ↔ postgres ролью не поддерживается |
| `caddy_naive_users пуст (NAIVE_USER / NAIVE_PASSWORD)` | не загружен `.env`: `set -a; . ./.env; set +a` |
