# Присоединение `oci-pve` к домашнему `nexus-cluster`

Статус на 2026-09-04: **нода добавлена в кластер, но изолирована** — corosync
не собирает кольцо с домашними нодами. Ниже разбор + TODO.

## Текущее фактическое состояние

`oci-pve` — полноценный член кластера, не QDevice:

```
pvecm status (на oci-pve):
  Name: nexus-cluster   Config Version: 5   Transport: knet
  Node ID: 0x00000003
  Nodes: 1   Quorate: No   Total votes: 1 / Expected 4   Quorum: 3  → Activity blocked
```

`/etc/corosync/corosync.conf` (одинаковый на всех нодах, Config Version 5):

```
node bare-pve  nodeid 1  ring0_addr 192.168.100.30   ring1_addr 100.123.240.43
node pve-rog   nodeid 2  ring0_addr 192.168.100.20   ring1_addr 100.123.125.0
node oci-pve   nodeid 3  ring0_addr 100.103.202.8    ring1_addr 100.103.202.8
quorum device  model net  host 100.75.99.19 (Zenbook, corosync-qnetd)  algorithm ffsplit
totem: token 3000  consensus 4000  token_retransmits_before_loss_const 6  link_mode passive
```

`corosync-cfgtool -s` на `oci-pve`: обе линии (0 и 1) к nodeid 1 и 2 —
`disconnected`.

**Следствие:** домашний кластер (`bare-pve` + `pve-rog` + QDevice = 3 голоса,
кворум 3) — **кворумный, работает**. Отрезана только `oci-pve`: её `/etc/pve`
в read-only, LXC там не стартуют (на ней ничего и не крутилось).

## Почему не коннектится (разбор 2026-09-04)

### 1. link 0 для `oci-pve` не заработает никогда — by design

`ring0_addr` домашних нод = LAN `192.168.100.x`. У `oci-pve` (Oracle Cloud)
нет маршрута в домашнюю LAN, а домашние ноды шлют на link 0 со своего
LAN-адреса. Для `oci-pve` реально может работать только link 1 (все три ноды
на Tailscale-адресах). Сейчас вся связность OCI↔дом висит на **одном** линке
без фолбэка.

### 2. link 1 (Tailscale) сейчас тоже мёртв — но по внешней причине

`tailscale netcheck` на `bare-pve` **и** `pve-rog`:

```
* UDP: false
* IPv4: (no addr found)
* Nearest DERP: unknown (no response to latency probes)
```

Логи `tailscaled` на них: `derp.Send region N (fra/nue/waw): context deadline
exceeded` — ноды не достукиваются **ни до одного DERP-релея** (ни по UDP, ни
по TCP 443).

При этом обычный интернет на нодах жив (DNS/UDP, TCP 443 на 1.1.1.1 — OK) —
не работает именно egress до Tailscale DERP.

Контекст сети (важно): у домашнего роутера **нет публичного IP** (CGNAT у
провайдера), поэтому весь трафик OCI↔дом и «внешний Zenbook»↔дом идёт
Tailscale'ом, и раз обе стороны за NAT — **через DERP-релей**, не напрямую.
`bare-pve`/`pve-rog` при этом сами — Tailscale subnet-роутеры, шарят
`192.168.100.0/24` участникам тайлнета (подсеть одобрена для
`kashakdaniil@`-устройств; для `tagged-devices`, куда попадает `oci-pve`,
маршрут не одобрен — в её таблице маршрутов `192.168.100.0/24` нет, что и
подтверждает: link 0 по LAN-адресам для OCI мёртв).

Началось после флапа Realtek-NIC (`nic0` ушёл на 100 Мбит) и ручного ребута
обеих нод. Вероятные причины (не проверено до конца — доступ к нодам во
время диагностики отвалился):
- двойной NAT (домашний роутер → CGNAT провайдера) в принципе плохо держит
  UDP hole-punching; связь могла годами висеть на TCP-DERP, а флап/ребут
  оборвал эти долгоживущие TCP-сессии, и заново они не поднимаются;
- залипшая conntrack-таблица на домашнем роутере для этих двух хостов;
- баг UDP-egress / offload в `r8169` после переговоров линка;
- временный throttling UDP у провайдера после дневной закачки.

OCI-нода в другой сети → link 1 требует DERP-релей → раз домашние ноды до
DERP не доходят, link 1 OCI↔дом не поднимается → нода не входит в кворум.

### Что пробовали 2026-09-04 (диагностика, ничего в конфигах не менялось)

- `systemctl restart tailscaled` на `bare-pve` ×3 — `netcheck` остался
  `UDP: false`. Один раз после рестарта Zenbook↔bare-pve поднялся, потом
  снова отвалился.
- `ethtool -K nic0 tx/rx/gso/gro/tso off` на `bare-pve`, `netcheck` не
  изменился → **вернул как было** (`on/on/on`), проверено.
- Повторные `tailscale netcheck` на домашних нодах, похоже, добавили
  нагрузки на и без того еле живой Tailscale — к концу сессии SSH до обеих
  домашних нод перестал отвечать (сами ноды при этом здоровы: до потери
  доступа `bare-pve` был проверен через jump-хост `pve-rog` — 1 Гбит,
  кворум, все гости на месте).
- `corosync.conf`, `pvecm`, WireGuard — **не трогали**.

## TODO

### Разблокировать — вернуть Tailscale-egress домашним нодам

Нужен **локальный доступ к нодам** (LAN/консоль/IPMI) — по Tailscale они
сейчас то появляются, то отваливаются, диагностика удалённо ненадёжна.

- [ ] На `bare-pve` и `pve-rog`: `systemctl restart tailscaled`, затем
      `tailscale netcheck` — цель `UDP: true` + определившийся DERP.
- [ ] Если не помогло — `ethtool -K nic0 gso off gro off tso off` (r8169
      после переговоров линка кривит крупные пакеты), персистить udev-rule
      или `post-up` в `/etc/network/interfaces`.
- [ ] Перезагрузить **домашний роутер** — не ради внешней достижимости
      (её нет, CGNAT), а чтобы сбросить его conntrack/NAT-таблицу для
      исходящих сессий этих двух хостов. Обе ноды сломались идентично,
      Zenbook (был в той же сети) — нет → узкое место общее для них.
- [ ] Проверить, не режет ли провайдер исходящий UDP после дневной
      закачки (temporary anti-abuse) — `tailscale netcheck` с телефона на
      том же аплинке для сравнения.
- [ ] Критерий готовности: `tailscale ping 100.103.202.8` с домашней ноды
      проходит → `corosync-cfgtool -n` на `oci-pve` даёт link 1
      `connected` → `pvecm status` = `Nodes: 3` / `Total votes: 4`.
- [ ] Крайний вариант, если Tailscale-egress так и не стабилизируется —
      USB-NIC на домашних нодах под управляющий/corosync-трафик, либо
      сразу перейти к WireGuard-туннелю (ниже) и не зависеть от DERP.

### Убрать хрупкость дизайна (правится в `corosync.conf`, Config Version bump)

- [ ] **link 0 не должен ссылаться на недостижимые для `oci-pve` адреса.**
      Варианты:
      - все три ноды на Tailscale-адресах в link 0, LAN-линк убрать/сделать
        link 1 (у домашних нод LAN всё равно быстрее и поднимется первым при
        `link_mode: passive`);
      - **или** отдельный WireGuard site-to-site туннель дом↔OCI, corosync
        поверх него (не зависит от Tailscale DERP вообще) — исходный план из
        README TODO;
      - **или** демоут `oci-pve` до QDevice-only (`pvecm qdevice` уже занят
        Zenbook'ом — тогда Zenbook освобождается / становится вторым
        арбитром). Проще всего, но теряется идея «третья полноценная нода».
- [ ] Поднять corosync-таймауты под WAN-линк: `token` 3000 → ~10000,
      `token_retransmits_before_loss_const` оставить, `consensus`
      пропорционально. Иначе даже при живом Tailscale джиттер OCI↔дом будет
      периодически ронять кольцо (тот же флап, что ловили на LAN при
      перегрузе).
- [ ] Решить, что делать с `expected votes: 4` пока `oci-pve` отрезана:
      сейчас домашние 3 голоса ровно на пороге кворума — **потеря одной
      домашней ноды или QDevice = потеря кворума на всём кластере**.
      До починки OCI-линка безопаснее временно вынести её:
      `pvecm delnode oci-pve` (с домашней ноды), вернуть после.

### Автоматизация (в этот репозиторий)

- [ ] Присоединение к кластеру сейчас сделано руками (`pvecm add` где-то в
      истории — в `bootstrap.sh.tpl` этого нет). Решить: оставить ручным
      шагом с чеклистом в README, либо добавить в Stage 2 опциональный блок
      (`join_cluster` toggle в `oci/config`, `pvecm add <home-node> --link0
      <ts-ip> --link1 <ts-ip>` + предраскатка corosync-таймаутов).
- [ ] Если через WireGuard — туннель поднимать в Stage 2 (ключи из
      `oci/api`), до `pvecm add`.

## Диагностика (справочно)

```bash
# С домашней ноды — жив ли Tailscale-путь до OCI:
ssh bare-pve 'tailscale netcheck; tailscale ping 100.103.202.8'

# На oci-pve (ssh debian@100.103.202.8 + sudo -i) — состояние линий:
corosync-cfgtool -s
corosync-cfgtool -n
pvecm status
journalctl -u corosync -u tailscaled --no-pager --since "10 min ago" | grep -iE "knet|link|derp|token"

# Слушает ли corosync на нужном адресе:
ss -ulpn | grep corosync   # ожидаем <tailscale-ip>:5405 и :5406
```
