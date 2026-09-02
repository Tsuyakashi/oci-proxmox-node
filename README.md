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

## Использование

```bash
cp terraform.tfvars.example terraform.tfvars
# заполнить секреты (или через Vault-wrapper, как в iac-proxmox-lab)

terraform init \
  -backend-config="access_key=$MINIO_ACCESS_KEY" \
  -backend-config="secret_key=$MINIO_SECRET_KEY"

terraform plan
terraform apply
```

После apply — `terraform output public_ip`, ждать ~2-3 минуты на установку
пакетов + ребут, затем открыть `https://<public_ip>:8006`.

## TODO / открытые вопросы

- [ ] Проверить, что `proxmox-default-kernel` вообще ставится на OCI Ampere
  (нестандартное железо/BIOS облачного провайдера — не факт, что модули
  ZFS/etc заведутся без танцев)
- [ ] Решить: полноценный член кластера (нужен WireGuard-туннель + multi-link
  corosync с увеличенным token timeout) или только QDevice-арбитр
  (проще, не требует VPN — PVE-ноды сами дозваниваются наружу)
- [ ] Секреты OCI API-ключа перенести в Vault по аналогии с
  `vault-apply-wrapper.sh`
- [ ] Если решится полноценное членство — добавить `oci_core_security_list`
  правила под corosync knet (5405-5412/udp) вместо ingress_ports_udp=[]
