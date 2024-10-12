#!/bin/bash

clear
mkdir -p ~/.cloudshell && touch ~/.cloudshell/no-apt-get-warning
sudo apt-get update -y --fix-missing && sudo apt-get install wireguard-tools jq -y --fix-missing

private_key="${1:-$(wg genkey)}"
public_key="${2:-$(echo "${private_key}" | wg pubkey)}"
api_url="https://api.cloudflareclient.com/v0i1909051800"

send_request() {
    curl -s -H 'user-agent:' -H 'content-type: application/json' -X "$1" "${api_url}/$2" "${@:3}"
}
send_secure_request() {
    send_request "$1" "$2" -H "authorization: Bearer $3" "${@:4}"
}

initial_response=$(send_request POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"${public_key}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")

install_id=$(echo "$initial_response" | jq -r '.result.id')
auth_token=$(echo "$initial_response" | jq -r '.result.token')

config_response=$(send_secure_request PATCH "reg/${install_id}" "$auth_token" -d '{"warp_enabled":true}')

peer_public_key=$(echo "$config_response" | jq -r '.result.config.peers[0].public_key')
peer_host=$(echo "$config_response" | jq -r '.result.config.peers[0].endpoint.host')
ipv4_address=$(echo "$config_response" | jq -r '.result.config.interface.addresses.v4')
ipv6_address=$(echo "$config_response" | jq -r '.result.config.interface.addresses.v6')
port=$(echo "$peer_host" | sed 's/.*:\([0-9]*\)$/\1/')
peer_host=$(echo "$peer_host" | sed 's/\(.*\):[0-9]*/162.159.193.5/')
allowed_ips_url="https://raw.githubusercontent.com/hempboy/wgam_warp_gen/refs/heads/main/ip.txt"
if [[ -n "$allowed_ips_url" ]]; then
    # Загружаем содержимое файла и проверяем, что это текст
    allowed_ips=$(curl -s "$allowed_ips_url" | grep -v '^<')
    if [[ -z "$allowed_ips" ]]; then
        echo "Ошибка: файл пуст или содержит некорректные данные."
        allowed_ips="0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1"
    else
        allowed_ips=$(echo "$allowed_ips" | tr '\n' ',' | sed 's/,$//')
    fi
else
    allowed_ips="0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1"
fi

wg_config=$(cat <<EOF
[Interface]
PrivateKey = ${private_key}
S1 = 0
S2 = 0
Jc = 4
Jmin = 40
Jmax = 70
H1 = 1
H2 = 2
H3 = 3
H4 = 4
Address = ${ipv4_address}, ${ipv6_address}
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001

[Peer]
PublicKey = ${peer_public_key}
AllowedIPs = ${allowed_ips}
Endpoint = ${peer_host}:${port}
EOF
)

clear
temp_file="WARP.conf"
echo "${wg_config}" > "$temp_file"
upload_response=$(curl -F "file=@$temp_file" -F "title=WARP.conf" https://file.io)
rm "$temp_file"
download_link=$(echo "$upload_response" | jq -r '.link')
if [[ "$download_link" != "null" ]]; then
    echo "Ссылка для скачивания WARP.conf: $download_link"
else
    echo "Ошибка при загрузке файла: $upload_response"
fi
