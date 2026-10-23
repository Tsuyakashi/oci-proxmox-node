#!/bin/bash
# wg-client — управление клиентами WireGuard на ноде (oci-ts).
#
#   wg-client add <name> [<name> ...]   создать клиентов: ключи + PSK, следующий
#                                       свободный IP, пир в wg0, конфиг + QR
#   wg-client show <name>               снова показать конфиг и QR
#   wg-client rm <name> [<name> ...]    удалить клиента (пир + файлы)
#   wg-client ls                        список: имя, IP, последний хендшейк
#
# Конфиги клиентов — /etc/wireguard/clients/<name>.conf (0600, root).
# Endpoint по умолчанию — внешний IP ноды (reserved), переопределяется
# WG_ENDPOINT=host:port; DNS клиентов — WG_DNS (по умолчанию 1.1.1.1).

set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"

WG_IF=wg0
DIR=/etc/wireguard/clients
DNS="${WG_DNS:-1.1.1.1}"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 1 ] || usage

wg show "$WG_IF" >/dev/null 2>&1 || { echo "интерфейс $WG_IF не поднят" >&2; exit 1; }
mkdir -p "$DIR"
chmod 700 "$DIR"

SERVER_PUB=$(wg show "$WG_IF" public-key)
PORT=$(wg show "$WG_IF" listen-port)
SERVER_ADDR=$(ip -4 -o addr show "$WG_IF" | awk '{print $4; exit}')   # 10.66.66.1/24
PREFIX=${SERVER_ADDR%.*}                                              # 10.66.66
ENDPOINT="${WG_ENDPOINT:-$(curl -4 -fsS --max-time 5 https://checkip.amazonaws.com):${PORT}}"

valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "плохое имя: '$1' (только A-Z a-z 0-9 _ -)" >&2; return 1; }; }

need_qrencode() {
    command -v qrencode >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qrencode >/dev/null
}

next_ip() {
    local used i
    used=$(wg show "$WG_IF" allowed-ips | grep -oE "${PREFIX//./\\.}\.[0-9]+" || true)
    for i in $(seq 2 254); do
        grep -qx "${PREFIX}.${i}" <<<"$used" || { echo "${PREFIX}.${i}"; return; }
    done
    echo "в ${PREFIX}.0/24 нет свободных адресов" >&2
    return 1
}

show_one() {
    local conf="$DIR/$1.conf"
    [ -f "$conf" ] || { echo "нет клиента '$1'" >&2; return 1; }
    need_qrencode
    echo "===== $1 ====="
    cat "$conf"
    echo
    qrencode -t ansiutf8 < "$conf"
}

add_one() {
    local name=$1 ip priv pub psk
    valid_name "$name"
    if [ -f "$DIR/$name.conf" ]; then
        echo "'$name' уже есть — показываю существующий конфиг" >&2
        show_one "$name"
        return
    fi

    ip=$(next_ip)
    priv=$(wg genkey)
    pub=$(wg pubkey <<<"$priv")
    psk=$(wg genpsk)

    wg set "$WG_IF" peer "$pub" preshared-key <(echo "$psk") allowed-ips "${ip}/32"

    umask 077
    cat >"$DIR/$name.conf" <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${ip}/32
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUB}
PresharedKey = ${psk}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    echo "$pub" >"$DIR/$name.pub"

    show_one "$name"
}

rm_one() {
    local name=$1
    valid_name "$name"
    [ -f "$DIR/$name.pub" ] || { echo "нет клиента '$name'" >&2; return 1; }
    wg set "$WG_IF" peer "$(cat "$DIR/$name.pub")" remove
    rm -f "$DIR/$name.conf" "$DIR/$name.pub"
    echo "удалён: $name"
}

list_all() {
    local f name pub ip hs
    printf '%-20s %-15s %s\n' NAME IP LAST_HANDSHAKE
    for f in "$DIR"/*.pub; do
        [ -e "$f" ] || { echo "(клиентов нет)"; return; }
        name=$(basename "$f" .pub)
        pub=$(cat "$f")
        ip=$(wg show "$WG_IF" allowed-ips | awk -v p="$pub" '$1==p {print $2}')
        hs=$(wg show "$WG_IF" latest-handshakes | awk -v p="$pub" '$1==p {print $2}')
        if [ -z "${hs:-}" ] || [ "$hs" = 0 ]; then hs=never; else hs=$(date -d "@$hs" '+%F %T'); fi
        printf '%-20s %-15s %s\n' "$name" "${ip:-?}" "$hs"
    done
}

cmd=$1
shift
case "$cmd" in
    add)
        [ $# -ge 1 ] || usage
        for n in "$@"; do add_one "$n"; done
        wg-quick save "$WG_IF"
        ;;
    rm)
        [ $# -ge 1 ] || usage
        for n in "$@"; do rm_one "$n"; done
        wg-quick save "$WG_IF"
        ;;
    show)
        [ $# -eq 1 ] || usage
        show_one "$1"
        ;;
    ls) list_all ;;
    *) usage ;;
esac
