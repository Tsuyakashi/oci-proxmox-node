#!/usr/bin/env python3
"""
scripts/import-debian-image.py

Разовый шаг, ВНЕ Terraform — импортирует официальный Debian 13 (trixie)
generic-cloud arm64 образ в OCI как custom image с launchMode=CUSTOM +
firmware=UEFI_64 (ARM грузится только через UEFI). Эта комбинация не
выставляется ни через `oci` CLI, ни через терраформовский provider
`oracle/oci` (открытый баг в terraform-provider-oci — launch_options не
принимает произвольную комбинацию для QCOW2-импорта), поэтому REST-запрос
подписывается вручную.

Источник рецепта (проверено автором на pve-manager/9.2.9, VM.Standard.A1.Flex,
август 2026): https://www.dima.pm/proxmox-ve-9-2-arm64-on-oracle-cloud/

Использование:
    pip install oci requests --break-system-packages
    python3 scripts/import-debian-image.py --bucket os-images

Требует:
  - ~/.oci/config уже настроен (тот же, что уже используешь для `oci` CLI)
  - Бакет с именем --bucket уже существует в Object Storage (создать через
    консоль или `oci os bucket create --name os-images
    --compartment-id <compartment_ocid>`)
  - Файл debian-13-genericcloud-arm64.qcow2 уже лежит в этом бакете —
    скрипт сам его туда не заливает, см. шаги ниже

Что делать руками ДО запуска этого скрипта:
    curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2
    curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
    sha512sum -c SHA512SUMS --ignore-missing
    oci os object put --bucket-name os-images \
      --file debian-13-genericcloud-arm64.qcow2 \
      --name debian-13-genericcloud-arm64.qcow2

Результат — печатает image_id. Его нужно положить в oci/config как
image_ocid (см. vault-policy-init.sh / README).
"""

import argparse
import sys

try:
    import oci
    import requests
    from oci.signer import Signer
except ImportError:
    print("error: pip install oci requests --break-system-packages", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", default="os-images", help="Object Storage bucket с загруженным .qcow2")
    parser.add_argument("--object-name", default="debian-13-genericcloud-arm64.qcow2")
    parser.add_argument("--display-name", default="debian-13-arm64")
    parser.add_argument("--shape", default="VM.Standard.A1.Flex", help="Шейп, под который добавляется совместимость образа")
    parser.add_argument("--os-version", default="13")
    args = parser.parse_args()

    cfg = oci.config.from_file()
    compute = oci.core.ComputeClient(cfg)
    namespace = oci.object_storage.ObjectStorageClient(cfg).get_namespace().data

    signer = Signer(
        tenancy=cfg["tenancy"],
        user=cfg["user"],
        fingerprint=cfg["fingerprint"],
        private_key_file_location=cfg["key_file"],
    )

    body = {
        "compartmentId": cfg["tenancy"],
        "displayName": args.display_name,
        "launchMode": "CUSTOM",
        "launchOptions": {
            "bootVolumeType": "PARAVIRTUALIZED",
            "networkType": "PARAVIRTUALIZED",
            "remoteDataVolumeType": "PARAVIRTUALIZED",
            "firmware": "UEFI_64",
            "isConsistentVolumeNamingEnabled": False,
            "isPvEncryptionInTransitEnabled": False,
        },
        "imageSourceDetails": {
            "sourceType": "objectStorageTuple",
            "namespaceName": namespace,
            "bucketName": args.bucket,
            "objectName": args.object_name,
            "sourceImageType": "QCOW2",
            "operatingSystem": "Debian",
            "operatingSystemVersion": args.os_version,
        },
    }

    print(f"Импортирую {args.object_name} из бакета {args.bucket}...")
    r = requests.post(
        f'https://iaas.{cfg["region"]}.oraclecloud.com/20160918/images',
        json=body, auth=signer, timeout=60,
    )
    r.raise_for_status()
    image_id = r.json()["id"]
    print(f"Импорт запущен: {image_id}")
    print("Ожидание AVAILABLE (~6 минут)...")

    img = oci.wait_until(
        compute, compute.get_image(image_id),
        "lifecycle_state", "AVAILABLE",
        max_wait_seconds=2400,
    ).data

    assert img.launch_options.firmware == "UEFI_64", (
        f"firmware оказался {img.launch_options.firmware}, ожидался UEFI_64 — "
        "образ фиксирует firmware на моменте импорта, пересоздавать заново"
    )

    compute.add_image_shape_compatibility_entry(
        image_id=image_id, shape_name=args.shape,
    )

    print()
    print(f"Готово: {image_id}")
    print(f"Положи это значение в oci/config как image_ocid:")
    print(f'  vault kv patch oci/config image_ocid="{image_id}"')


if __name__ == "__main__":
    main()
