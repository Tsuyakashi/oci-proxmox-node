# oci-proxmox-node

Отдельный Terraform-проект (провайдер `oracle/oci`), поднимающий Always-Free
инстанс в Oracle Cloud и разворачивающий на нём Proxmox VE с нуля через
cloud-init bootstrap. Не связан с `iac-proxmox-lab` (там `bpg/proxmox` рулит
уже существующим кластером) — отдельный репозиторий, отдельный стейт,
отдельный бэкенд-key, чтобы не пересекаться.

## Что делает

1. `network.tf` — VCN, subnet, internet gateway, security list (открыты 22 и
   8006/tcp наружу по умолчанию, список портов настраивается)
2. `instance.tf` — сам компьют-инстанс (по умолчанию `VM.Standard.A1.Flex`,
   ARM Ampere always-free, 2 OCPU/12GB по текущим урезанным лимитам)
3. `cloud-init/bootstrap.sh.tpl` — при первом старте инстанса: добавляет
   pve-репозиторий, ставит `proxmox-ve`, настраивает `vmbr0` поверх
   единственного облачного интерфейса, перезагружается

## Важные ограничения

- **Образ обязан быть Debian 12 (bookworm), не Ubuntu** — PVE официально
  ставится только поверх Debian. Проверить доступные образы:
  `oci compute image list --compartment-id <ocid> --operating-system Debian`
- **Ampere A1 не поддерживает nested virtualization** — реальные QEMU VM
  внутри PVE на этой ноде не поднимутся, только LXC-контейнеры
- Always-Free лимит на Ampere A1 — 2 OCPU / 12GB суммарно на все инстансы
  в тенанси (с июня 2026 срезано с прежних 4/24)
- Присоединение к существующему кластеру (`nexus-cluster`) — **не** часть
  этого Terraform-проекта, делается вручную после первого старта
  (`pvecm add ... --link0 <lan-ip> --link1 <oci-public-ip>` или через
  QDevice-net вместо полного членства — см. обсуждение в чате)

## Конфиг и секреты — только в Vault, никакого `terraform.tfvars`

Тот же Vault (CT 300), что уже использует `iac-proxmox-lab`, но
**отдельный KV-v2 mount `oci/`** с двумя путями:

- `oci/api` — секреты (tenancy/user/fingerprint/приватный ключ)
- `oci/config` — весь остальной конфиг (регион, compartment, шейп,
  ресурсы, hostname, ssh-ключ, порты) — не секрет по природе, но тоже
  только в Vault, не в файле на диске

```bash
export VAULT_ADDR=http://192.168.100.200:8200

# 1. Включить mount oci/ + создать policy oci-proxmox-node (один раз)
./scripts/vault-policy-init.sh

# 2. Если не под root — назначить policy своему логину и перелогиниться
vault write auth/userpass/users/<ты> \
  token_policies="operator-manual-apply,oci-proxmox-node"
vault login -method=userpass username=<ты>

# 3. Секреты
vault kv put oci/api \
  tenancy_ocid="ocid1.tenancy.oc1..xxx" \
  user_ocid="ocid1.user.oc1..xxx" \
  fingerprint="xx:xx:xx:..." \
  private_key=@/home/tsu/.oci/oci_api_key.pem

# 4. Весь остальной конфиг — тоже в Vault, не в tfvars
vault kv put oci/config \
  region="eu-frankfurt-1" \
  compartment_ocid="ocid1.compartment.oc1..xxx" \
  availability_domain="xxxx:EU-FRANKFURT-1-AD-1" \
  image_ocid="ocid1.image.oc1..xxx" \
  instance_shape="VM.Standard.A1.Flex" \
  instance_ocpus="2" \
  instance_memory_gb="12" \
  hostname="oci-pve" \
  ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" \
  pve_version_branch="bookworm" \
  ingress_ports_tcp='[22, 8006]' \
  ingress_ports_udp='[]'
```

`ingress_ports_tcp`/`ingress_ports_udp` хранятся как HCL-литерал строкой
(`"[22, 8006]"`) — Terraform сам парсит такую строку из `TF_VAR_*` для
`list(number)`, без доп. обработки в wrapper'е.

`proxmox/minio-credentials` заводить не нужно — уже существует, общая
инфраструктура с `iac-proxmox-lab`.

## Использование

```bash
source scripts/vault-apply-wrapper.sh   # один раз на сессию шелла — тянет
                                          # ВСЁ (секреты + конфиг) из Vault
terraform init
terraform plan
terraform apply
```

Без `vault login`/policy — `apply` упадёт на первой же переменной
(`No value for required variable`), не подхватит молча ничего с диска.

После apply — `terraform output public_ip`, ждать ~2-3 минуты на установку
пакетов + ребут, затем открыть `https://<public_ip>:8006`.

## Структура

```
oci-proxmox-node/
├── backend.tf              # terraform{} + required_providers + backend "s3" — ЕДИНСТВЕННОЕ место с этим блоком
├── providers.tf             # только provider "oci" { ... }
├── variables.tf
├── network.tf                # VCN/subnet/IGW/security list
├── instance.tf                # сам инстанс + cloud-init рендер
├── outputs.tf
├── scripts/
│   ├── vault-policy-init.sh    # включает mount oci/ + policy oci-proxmox-node (запустить один раз)
│   └── vault-apply-wrapper.sh # лениво тянет секреты из Vault на `terraform` в этой директории
└── cloud-init/
    └── bootstrap.sh.tpl      # установка Proxmox VE поверх Debian 12
```

## TODO / открытые вопросы

- [ ] Проверить, что `proxmox-default-kernel` вообще ставится на OCI Ampere
  (нестандартное железо/BIOS облачного провайдера — не факт, что модули
  ZFS/etc заведутся без танцев)
- [ ] Решить: полноценный член кластера (нужен WireGuard-туннель + multi-link
  corosync с увеличенным token timeout) или только QDevice-арбитр
  (проще, не требует VPN — PVE-ноды сами дозваниваются наружу)
- [ ] Если решится полноценное членство — добавить `oci_core_security_list`
  правила под corosync knet (5405-5412/udp) вместо ingress_ports_udp=[]
