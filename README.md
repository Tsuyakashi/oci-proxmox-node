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

## Секреты (Vault)

Тот же Vault (CT 300), что уже использует `iac-proxmox-lab` — тот же mount
`proxmox/`, никакого отдельного mount под этот проект заводить не нужно.

```bash
# 1. Расширить operator-manual-apply policy доступом к новому пути
#    (нужно один раз; без этого шага kv put/get на proxmox/oci-api
#    падает с 403 "please ensure client's policies grant access to path")
export VAULT_ADDR=http://192.168.100.200:8200
./scripts/vault-policy-init.sh

# 2. Залогиниться (если сессия ещё не залогинена)
vault login -method=userpass username=<ты>

# 3. Засеять сам секрет — приватный ключ целиком, не путь!
vault kv put proxmox/oci-api \
  tenancy_ocid="ocid1.tenancy.oc1..xxx" \
  user_ocid="ocid1.user.oc1..xxx" \
  fingerprint="xx:xx:xx:..." \
  private_key=@/home/tsu/.oci/oci_api_key.pem
```

`proxmox/minio-credentials` заводить не нужно — уже существует, заведён
`iac-proxmox-lab`, этот проект просто его переиспользует.

## Использование

```bash
cp terraform.tfvars.example terraform.tfvars
# заполнить НЕсекретные поля (region/compartment/shape/сеть)

source scripts/vault-apply-wrapper.sh   # один раз на сессию шелла

terraform init
terraform plan
terraform apply
```

Wrapper подтягивает OCI API-креды и MinIO backend-креды из Vault при первом
вызове `terraform` в этой директории за сессию, приватный ключ пишет во
временный файл 0600 в `/tmp` и подчищает его при выходе из шелла.

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
├── terraform.tfvars.example   # только несекретный конфиг
├── scripts/
│   ├── vault-policy-init.sh    # расширяет operator-manual-apply доступом к proxmox/oci-api (запустить один раз)
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
