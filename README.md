# oci-proxmox-node

Terraform-проект (провайдер `oracle/oci`), поднимающий Always-Free ARM
инстанс (`VM.Standard.A1.Flex`) в Oracle Cloud и разворачивающий на нём
**Proxmox VE с официальной поддержкой ARM64** (шипнута в августе 2026).
Не связан с `iac-proxmox-lab` (там `bpg/proxmox` рулит домашним x86-кластером)
— отдельный репозиторий, отдельный стейт, отдельный Vault-mount.

Источник рецепта, проверено автором на `pve-manager/9.2.9`,
`VM.Standard.A1.Flex`, август 2026:
https://www.dima.pm/proxmox-ve-9-2-arm64-on-oracle-cloud/

## Важные ограничения — прочитать перед тем, как начинать

- **`VM.Standard.A1.Flex` не даёт EL2** → нет nested virtualization →
  **только LXC-контейнеры, никаких QEMU VM**. Если нужны полноценные VM —
  это не тот шейп (потребовалось бы `BM.Standard.A1.160`, bare metal, уже
  не Always Free).
- **Образ — Debian 13 (trixie), не 12 (bookworm)** — ARM-сборка Proxmox VE
  существует только под trixie.
- **Oracle не публикует Debian как готовый platform image** — образ
  импортируется вручную (см. Шаг 1 ниже), это единственный шаг, требующий
  скрипта вне Terraform.
- **Веб-GUI (8006) закрыт наружу** — доступ через Tailscale, не через
  публичный IP напрямую.
- Always-Free лимит на Ampere A1 — 2 OCPU / 12GB суммарно на все
  инстансы в тенанси (актуально на момент написания).
- Присоединение к домашнему кластеру (`nexus-cluster`) — из более раннего
  обсуждения в чате — здесь не реализовано; эта нода стоит отдельно.

## Шаг 1 — импорт образа (разово, вне Terraform)

Комбинация `launchMode=CUSTOM` + `firmware=UEFI_64` (ARM грузится только
через UEFI) не выставляется через `oci` CLI или `terraform-provider-oci`
(открытый баг в провайдере) — только прямым REST-запросом.

```bash
# Скачать и проверить официальный Debian generic-cloud arm64 образ
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
sha512sum -c SHA512SUMS --ignore-missing

# Бакет + загрузка (тот же ~/.oci/config, что уже настроен для CLI)
oci os bucket create --name os-images --compartment-id <compartment_ocid>
oci os object put --bucket-name os-images \
  --file debian-13-genericcloud-arm64.qcow2 \
  --name debian-13-genericcloud-arm64.qcow2

# Импорт с нужной комбинацией launch_mode/firmware (скрипт лежит в
# корне репо, общий для всех environments — сейчас он один)
pip install oci requests --break-system-packages
python3 scripts/import-debian-image.py --bucket os-images
```

Скрипт напечатает `image_id` в конце — это значение идёт в `oci/config`
как `image_ocid` (см. Шаг 2).

## Шаг 2 — конфиг и секреты — только в Vault, никакого `terraform.tfvars`

Тот же Vault (CT 300), что уже использует `iac-proxmox-lab`, но
**отдельный KV-v2 mount `oci/`** с двумя путями:

- `oci/api` — секреты (OCI API-креды, `root_password` для веб-GUI,
  `tailscale_authkey`)
- `oci/config` — весь остальной конфиг (регион, compartment, шейп,
  ресурсы, размеры дисков, hostname, ssh-ключ, подсеть контейнеров)

```bash
export VAULT_ADDR=http://192.168.100.200:8200

# 1. Включить mount oci/ + создать policy oci-proxmox-node (один раз,
#    запускается из корня репо — общий для всех environments)
./scripts/vault-policy-init.sh

# 2. Если не под root — назначить policy своему логину и перелогиниться
vault write auth/userpass/users/<ты> \
  token_policies="operator-manual-apply,oci-proxmox-node"
vault login -method=userpass username=<ты>

# 3. Секреты. tailscale_authkey — Settings -> Keys в консоли Tailscale
vault kv put oci/api \
  tenancy_ocid="ocid1.tenancy.oc1..xxx" \
  user_ocid="ocid1.user.oc1..xxx" \
  fingerprint="xx:xx:xx:..." \
  private_key=@/home/tsu/.oci/oci_api_key.pem \
  root_password="..." \
  tailscale_authkey="tskey-auth-..."

# 4. Весь остальной конфиг
vault kv put oci/config \
  region="eu-frankfurt-1" \
  compartment_ocid="ocid1.compartment.oc1..xxx" \
  availability_domain="xxxx:EU-FRANKFURT-1-AD-1" \
  image_ocid="<из Шага 1>" \
  instance_shape="VM.Standard.A1.Flex" \
  instance_ocpus="2" \
  instance_memory_gb="12" \
  boot_volume_size_gb="60" \
  block_volume_size_gb="140" \
  hostname="oci-pve" \
  ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" \
  container_subnet="10.10.10.0/24" \
  pve_version_branch="trixie"
```

`proxmox/minio-credentials` заводить не нужно — уже существует, общая
инфраструктура с `iac-proxmox-lab`.

**Выбирай `hostname` окончательно сразу** — Proxmox зашивает его в
`/etc/pve/nodes/<name>/`, переименование задним числом мучительно
(`/etc/pve` — FUSE-файловая система, `cp -a` там молча не срабатывает).

## Шаг 3 — apply

```bash
cd env/pve-node
source ../../scripts/vault-apply-wrapper.sh   # один раз на сессию шелла
terraform init
terraform plan
terraform apply
```

Без `vault login`/policy — `apply` упадёт на первой же переменной
(`No value for required variable`), не подхватит молча ничего с диска.

## Что происходит после apply (~60–90 минут, большая часть — ожидание)

Terraform поднимает сеть, инстанс (boot volume + отдельный block volume
под ZFS), резервирует публичный IP. Дальше двухстадийный cloud-init:

1. **Stage 1** (сразу при первом старте) — хостнейм/`/etc/hosts`,
   pve-репозиторий (trixie), смена ядра на `proxmox-default-kernel`
   (grub one-shot: если новое ядро не взлетит, следующий обычный ребут
   вернёт Debian — safety net), затем ребут.
2. **Stage 2** (systemd oneshot, срабатывает после ребута на новом ядре) —
   установка `proxmox-ve`, удаление debian-ядер, пароль root для GUI,
   ZFS-пул `tank` на втором диске, NAT-мост `vmbr0` для контейнеров
   (OCI vNIC пропускает трафик только со своим MAC — прямой bridge на
   физический интерфейс не пропустит гостевой трафик), dnsmasq под DHCP
   контейнерам, Tailscale (`--advertise-routes` на `container_subnet`).

Прогресс — `ssh debian@<public_ip> 'tail -f /var/log/pve-bootstrap.log'`
(вывод и Stage 1, и Stage 2 пишется в один файл).

## Шаг 4 — одобрить route в Tailscale (руками, один раз)

`tailscale up --advertise-routes` не включает маршрут автоматически —
зайти в https://login.tailscale.com/admin/machines → найти ноду по
`hostname` → **Edit route settings** → одобрить `container_subnet`.

После этого:
- Веб-GUI: `https://<tailscale-ip-ноды>:8006`, `root`, realm **Linux PAM**
- Контейнеры на `container_subnet` достижимы с любого устройства в
  тайлнете напрямую, без port forwarding

## Проверка

```bash
ssh debian@<public_ip>
uname -r                          # ожидается *-pve, не *-cloud-arm64
zpool status tank                 # ONLINE
systemctl status dnsmasq          # active, слушает на адресе container_subnet
tailscale status
```

Создать тестовый LXC (arm64-шаблоны Proxmox публикует напрямую):

```bash
pveam update
pveam download local debian-13-standard_13.6-1_arm64.tar.zst
pct create 9000 local:vztmpl/debian-13-standard_13.6-1_arm64.tar.zst \
  --hostname nat-test --arch arm64 --ostype debian \
  --cores 1 --memory 512 --rootfs tank:2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth \
  --unprivileged 1 --features nesting=1 --start 1
pct exec 9000 -- ip -br addr show eth0   # ожидается адрес из container_subnet
pct exec 9000 -- apt-get update          # реальный TCP+TLS+DNS наружу
pct stop 9000 && pct destroy 9000
```

## Отладка без консоли

Serial console log доступен через API даже без Oracle Cloud Agent —
полезно, если SSH ещё не поднялся или Stage 2 упал по дороге:

```bash
# из env/pve-node
INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null || echo "<ocid1.instance...>")

HISTORY_ID=$(oci compute console-history capture \
  --instance-id "$INSTANCE_ID" \
  --query 'data.id' --raw-output)

# подождать несколько секунд, пока capture перейдёт в SUCCEEDED
oci compute console-history get --instance-console-history-id "$HISTORY_ID" \
  --query 'data."lifecycle-state"' --raw-output

oci compute console-history get-content \
  --instance-console-history-id "$HISTORY_ID" \
  --file - --length 1048576
```

## Структура

Стандартный `mod/` + `env/` split (тот же паттерн, что `iac-proxmox-lab`,
только с сокращёнными именами папок). `mod/oci-pve-node` — вся
инфраструктура (сеть, инстанс, диски, reserved IP), без
`backend`/`provider` — их задаёт вызывающий root-модуль. Сейчас всего один
environment (`env/pve-node`), но при появлении второй ноды новый
environment переиспользует тот же модуль без копипаста.

```
oci-proxmox-node/
├── mod/
│   └── oci-pve-node/              # переиспользуемый модуль — БЕЗ backend/provider
│       ├── versions.tf            #   required_version + required_providers
│       ├── network.tf             #   VCN/subnet/IGW/security list (22/tcp + 41641/udp Tailscale, БЕЗ 8006)
│       ├── instance.tf            #   инстанс + block volume (ZFS) + reserved public IP
│       ├── variables.tf           #   всё, что нужно ресурсам — БЕЗ auth-переменных провайдера
│       ├── outputs.tf
│       └── cloud-init/bootstrap.sh.tpl  # двухстадийный: kernel swap -> reboot -> proxmox-ve+storage+network+tailscale
├── env/
│   └── pve-node/                  # ROOT MODULE — единственный environment на сегодня
│       ├── backend.tf             #   terraform{} + required_providers + backend "s3" — ЕДИНСТВЕННОЕ место с этим блоком
│       ├── providers.tf           #   provider "oci" { ... } — auth-переменные живут только здесь
│       ├── main.tf                #   вызов module.pve_node
│       ├── variables.tf           #   полный список — то, во что реально попадают TF_VAR_*
│       └── outputs.tf             #   реэкспорт из модуля
├── scripts/
│   ├── import-debian-image.py     # Шаг 1 — разовый импорт образа, вне Terraform
│   ├── vault-policy-init.sh       # включает mount oci/ + policy oci-proxmox-node (запустить один раз)
│   └── vault-apply-wrapper.sh     # лениво тянет секреты+конфиг из Vault на `terraform` в env/*
├── docs/
│   └── nexus-cluster-join.md      # присоединение к домашнему кластеру: текущее состояние, разбор, TODO
└── .gitignore
```

## TODO / открытые вопросы

- [ ] Проверить `is_pv_encryption_in_transit_enabled` на block volume —
  сейчас не выставлен (default false), совпадает с флагом, заданным при
  импорте образа, но комбинация не тестировалась апстримом
- [ ] Присоединение к домашнему `nexus-cluster` — нода **добавлена**
  (`pvecm`, Config Version 5, nodeid 3), но изолирована: corosync не
  собирает кольцо с домашними нодами. Разбор + TODO —
  [`docs/nexus-cluster-join.md`](docs/nexus-cluster-join.md)
- [ ] `tailscale_authkey` — если брать одноразовый (не reusable), придётся
  каждый пересоздание инстанса вручную генерить новый в консоли Tailscale
