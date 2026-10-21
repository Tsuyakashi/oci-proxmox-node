# env/micro-nodes — две Always-Free x86 ноды

`VM.Standard.E2.1.Micro` (AMD, 1/8 OCPU, 1 GB RAM), Ubuntu platform image,
без Proxmox. Замена двух LXC с A1-ноды, пока A1 во Франкфурте не выдаётся.

| нода     | роль                                   | публичные порты (NSG) |
| -------- | -------------------------------------- | --------------------- |
| `oci-wg` | WireGuard-сервер                       | 51820/udp             |
| `oci-ts` | Tailscale app-connector + форвард Valheim | 2456-2458/udp      |

Обе в тайлнете (SSH только через него, 22/tcp наружу закрыт). Общие для
подсети: 41641/udp (Tailscale p2p), ICMP 3/4.

## Перед apply

1. Capacity по Micro (`HARDWARE_NOT_SUPPORTED` = в этом AD шейпа нет вообще):
   ```bash
   oci compute compute-capacity-report create --compartment-id <tenancy_ocid> --availability-domain <AD> --shape-availabilities '[{"instanceShape":"VM.Standard.E2.1.Micro"}]' --query 'data."shape-availabilities"[0]."availability-status"'
   ```
2. `tailscale_authkey` в `oci/api` должен быть **reusable** — им регистрируются обе ноды.
3. `valheim_target_ip` в `env/micro-nodes/main.tf` — tailscale-IP LXC с Valheim
   (`tailscale ip -4` внутри контейнера). Пусто — форвард не ставится.
4. Удалить старую машину `oci-pve` в admin-консоли Tailscale, если ещё висит.

## Apply

```bash
cd env/micro-nodes
terraform init
terraform plan
terraform apply
```

Секреты/конфиг — тем же `tf-secrets` (`oci/api`, `oci/config`), ничего нового
в Vault заводить не нужно.

## После apply

Прогресс бутстрапа: `ssh ubuntu@oci-wg 'tail -f /var/log/node-bootstrap.log'`
(когда нода появится в тайлнете).

WireGuard: приватный ключ сервера генерируется на хосте, в state/Vault его нет.
Публичный — `sudo cat /etc/wireguard/server.pub`. Пир добавить:

```bash
sudo wg set wg0 peer <client_pubkey> allowed-ips 10.66.66.2/32
sudo wg-quick save wg0
```

Endpoint для клиентов — `public_ip` ноды `oci-wg` из `terraform output nodes`.

## Важно

- **Reserved IP под `prevent_destroy`.** `terraform destroy` на этом env упадёт —
  намеренно, чтобы не повторить потерю адреса, как с A1.
- **Bootstrap не перезапускается сам.** `user_data` и образ в `ignore_changes`;
  после правки `bootstrap.sh.tpl` пересборка только явно:
  `terraform apply -replace='module.micro_nodes.oci_core_instance.node["oci-ts"]'`.
- **Oracle iptables.** Образы Ubuntu от Oracle режут INPUT/FORWARD в
  `/etc/iptables/rules.v4`; bootstrap заменяет его открытым baseline —
  фильтрация на уровне security list + NSG.
- **Диск.** 2 × 50 GB = 100 из 200 GB Always Free. Если A1 поймается — в
  `oci/config` ужать `boot_volume_size_gb + block_volume_size_gb` до 100.
- **Если упал до `tailscale up`** — нода недоступна. Открыть аварийный SSH:
  `ssh_ingress_cidrs = ["<твой_ip>/32"]` в вызове модуля, apply, разобраться,
  убрать.
