#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
skybule="\e[1;36m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
skyblue() { echo -e "\e[1;36m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 定义常量
server_name="sing-box"
work_dir="/etc/sing-box"
config_dir="${work_dir}/config.json"
client_dir="${work_dir}/url.txt"

# 检查是否为root下运行
[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1

# 检查 sing-box 是否已安装
check_singbox() {
if [ -f "${work_dir}/${server_name}" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service sing-box status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active sing-box)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

# 设置socks5用户名和密码
read_socks_variables() {
    while true; do
        reading "请输入socks用户名: " socks_user
        if [[ ! -z "$socks_user" ]]; then
            green "你的socks用户名为: $socks_user"
            break
        else
            yellow "用户名不能为空，请重新输入"
        fi
    done

    while true; do
        reading "请输入socks密码，不能包含:和@符号: " socks_pass
        if [[ ! -z "$socks_pass" ]]; then
            green "你的socks密码为: $socks_pass"
            break
        else
            yellow "密码不能为空，请重新输入"
        fi
    done
}

# 检查 argo 是否已安装
check_argo() {
if [ -f "${work_dir}/argo" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service argo status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active argo)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

# 检查 nginx 是否已安装
check_nginx() {
if command -v nginx &>/dev/null; then
    if [ -f /etc/alpine-release ]; then
        rc-service nginx status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active nginx)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}

#根据系统类型安装、卸载依赖
manage_packages() {
    if [ $# -lt 2 ]; then
        red "Unspecified package name or action" 
        return 1
    fi

    action=$1
    shift

    for package in "$@"; do
        if [ "$action" == "install" ]; then
            if command -v "$package" &>/dev/null; then
                green "${package} already installed"
                continue
            fi
            yellow "正在安装 ${package}..."
            if command -v apt &>/dev/null; then
                apt install -y "$package"
            elif command -v dnf &>/dev/null; then
                dnf install -y "$package"
            elif command -v yum &>/dev/null; then
                yum install -y "$package"
            elif command -v apk &>/dev/null; then
                apk update
                apk add "$package"
            else
                red "Unknown system!"
                return 1
            fi
        elif [ "$action" == "uninstall" ]; then
            if ! command -v "$package" &>/dev/null; then
                yellow "${package} is not installed"
                continue
            fi
            yellow "正在卸载 ${package}..."
            if command -v apt &>/dev/null; then
                apt remove -y "$package" && apt autoremove -y
            elif command -v dnf &>/dev/null; then
                dnf remove -y "$package" && dnf autoremove -y
            elif command -v yum &>/dev/null; then
                yum remove -y "$package" && yum autoremove -y
            elif command -v apk &>/dev/null; then
                apk del "$package"
            else
                red "Unknown system!"
                return 1
            fi
        else
            red "Unknown action: $action"
            return 1
        fi
    done

    return 0
}

# 获取ip
get_realip() {
  ip=$(curl -s ipv4.ip.sb)
  if [ -z "$ip" ]; then
      ipv6=$(curl -s --max-time 1 ipv6.ip.sb)
      echo "[$ipv6]"
  else
      if echo "$(curl -s http://ipinfo.io/org)" | grep -qE 'Cloudflare|UnReal|AEZA|Andrei'; then
          ipv6=$(curl -s --max-time 1 ipv6.ip.sb)
          echo "[$ipv6]"
      else
          echo "$ip"
      fi
  fi
}

# 下载并安装 sing-box,cloudflared
install_singbox() {
    clear
    purple "正在安装sing-box中，请稍后..."
    # 判断系统架构
    ARCH_RAW=$(uname -m)
    case "${ARCH_RAW}" in
        'x86_64') ARCH='amd64' ;;
        'x86' | 'i686' | 'i386') ARCH='386' ;;
        'aarch64' | 'arm64') ARCH='arm64' ;;
        'armv7l') ARCH='armv7' ;;
        's390x') ARCH='s390x' ;;
        *) red "不支持的架构: ${ARCH_RAW}"; exit 1 ;;
    esac

    # 下载sing-box,cloudflared
    [ ! -d "${work_dir}" ] && mkdir -p "${work_dir}" && chmod 777 "${work_dir}"
    latest_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==false)][0].tag_name | sub("^v"; "")')
    curl -sLo "${work_dir}/${server_name}.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${latest_version}/sing-box-${latest_version}-linux-${ARCH}.tar.gz"
    curl -sLo "${work_dir}/qrencode" "https://github.com/eooce/test/releases/download/${ARCH}/qrencode-linux-${ARCH}"
    curl -sLo "${work_dir}/argo" "https://github.com/eooce/test/releases/download/$ARCH/bot13"
    tar -xzvf "${work_dir}/${server_name}.tar.gz" -C "${work_dir}/" && \
    mv "${work_dir}/sing-box-${latest_version}-linux-${ARCH}/sing-box" "${work_dir}/" && \
    rm -rf "${work_dir}/${server_name}.tar.gz" "${work_dir}/sing-box-${latest_version}-linux-${ARCH}"
    chown root:root ${work_dir} && chmod +x ${work_dir}/${server_name} ${work_dir}/argo ${work_dir}/qrencode

    # 是否安装socks5。不要直连！该协议用于cmliu/edgetunnel项目中的PROXYIP变量
    reading "\n是否安装socks5？【y/n】: " choice
    case "$choice" in
        [Yy])
            cd ${work_dir}
            read_socks_variables
        ;;
        [Nn]) exit 0 ;;
        *) red "无效的选择，请输入y或n" && menu ;;
    esac

   # 生成随机端口和密码
    vless_port=$(shuf -i 1000-65535 -n 1) 
    nginx_port=$(($vless_port + 1)) 
    tuic_port=$(($vless_port + 2))
    hy2_port=$(($vless_port + 3)) 
    socks_port=$(($vless_port + 4)) 
    uuid=$(cat /proc/sys/kernel/random/uuid)
    password=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24)
    output=$(/etc/sing-box/sing-box generate reality-keypair)
    private_key=$(echo "${output}" | awk '/PrivateKey:/ {print $2}')
    public_key=$(echo "${output}" | awk '/PublicKey:/ {print $2}')

    iptables -A INPUT -p tcp --dport 8001 -j ACCEPT 
    iptables -A INPUT -p tcp --dport $vless_port -j ACCEPT 
    iptables -A INPUT -p tcp --dport $nginx_port -j ACCEPT 
    iptables -A INPUT -p udp --dport $tuic_port -j ACCEPT 
    iptables -A INPUT -p udp --dport $hy2_port -j ACCEPT
    iptables -A INPUT -p tcp --dport $socks_port -j ACCEPT
    iptables -P FORWARD ACCEPT 
    iptables -P OUTPUT ACCEPT
    iptables -F
    manage_packages uninstall ufw firewalld iptables-persistent iptables-services > /dev/null 2>&1

    # 生成自签名证书
    openssl ecparam -genkey -name prime256v1 -out "${work_dir}/private.key"
    openssl req -new -x509 -days 3650 -key "${work_dir}/private.key" -out "${work_dir}/cert.pem" -subj "/CN=bing.com"

   # 生成配置文件
cat > "${config_dir}" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "output": "$work_dir/sb.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "Google",
        "address": "https://dns.google/dns-query",
        "address_resolver": "local"
      },
      {
        "tag": "local",
        "address": "local"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "geosite-openai"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "server": "wireguard"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "server": "block"
      }
    ],
    "final": "local",
    "disable_cache": false,
    "disable_expire": false
  },
  "inbounds": [
    {
        "tag": "vless-reality-vesion",
        "type": "vless",
        "listen": "::",
        "listen_port": $vless_port,
        "users": [
            {
              "uuid": "$uuid",
              "flow": "xtls-rprx-vision"
            }
        ],
        "tls": {
            "enabled": true,
            "server_name": "www.zara.com",
            "reality": {
                "enabled": true,
                "handshake": {
                    "server": "www.zara.com",
                    "server_port": 443
                },
                "private_key": "$private_key",
                "short_id": [
                  ""
                ]
            }
        }
    },

    {
        "tag": "vmess-ws",
        "type": "vmess",
        "listen": "::",
        "listen_port": 8001,
        "users": [
        {
            "uuid": "$uuid"
        }
    ],
    "transport": {
        "type": "ws",
        "path": "/vmess",
        "early_data_header_name": "Sec-WebSocket-Protocol"
        }
    },
 
    {
        "tag": "hysteria2",
        "type": "hysteria2",
        "listen": "::",
        "listen_port": $hy2_port,
        "users": [
            {
                "password": "$uuid"
            }
        ],
        "masquerade": "https://bing.com",
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$work_dir/cert.pem",
            "key_path": "$work_dir/private.key"
        }
    },
 
    {
        "tag": "tuic",
        "type": "tuic",
        "listen": "::",
        "listen_port": $tuic_port,
        "users": [
          {
            "uuid": "$uuid"
          }
        ],
        "congestion_control": "bbr",
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
        "certificate_path": "$work_dir/cert.pem",
        "key_path": "$work_dir/private.key"
       }
    },

    {
      "tag": "socks",
      "type": "socks",
      "listen": "::",
      "listen_port": $socks_port,
      "users": [
        {
          "username": "$socks_user",
          "password": "$socks_pass"
        }
      ]
    }

  ],
    "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    },
    {
      "type": "wireguard",
      "tag": "wireguard-out",
      "server": "162.159.195.100",
      "server_port": 4500,
      "local_address": [
        "172.16.0.2/32",
        "2606:4700:110:83c7:b31f:5858:b3a8:c6b1/128"
      ],
      "private_key": "mPZo+V9qlrMGCZ7+E6z2NI6NOV34PD++TpAR09PtCWI=",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [
        26,
        21,
        228
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-category-ads-all"
        ],
        "outbound": "block"
      },
      {
        "rule_set": [
          "geosite-openai"
        ],
        "outbound": "wireguard-out"
      },
      {
        "rule_set": [
          "geosite-netflix"
        ],
        "outbound": "wireguard-out"
      }
    ],
    "rule_set": [
      {
        "tag": "geosite-netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs"
      },
      {
        "tag": "geosite-openai",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs"
      },      
      {
        "tag": "geosite-category-ads-all",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
      }
    ],
    "auto_detect_interface": true,
    "final": "direct"
   },
   "experimental": {
      "cache_file": {
      "enabled": true,
      "path": "$work_dir/cache.db",
      "cache_id": "mycacheid",
      "store_fakeip": true
    }
  }
}
EOF
}
# debian/ubuntu/centos 守护进程
main_systemd_services() {
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/sing-box/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/argo.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --url http://localhost:8001 --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/sing-box/argo.log 2>&1"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    if [ -f /etc/centos-release ]; then
        yum install -y chrony
        systemctl start chronyd
        systemctl enable chronyd
        chronyc -a makestep
        yum update -y ca-certificates
        bash -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    fi
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    systemctl enable argo
    systemctl start argo
}
# 适配alpine 守护进程
alpine_openrc_services() {
    cat > /etc/init.d/sing-box << 'EOF'
#!/sbin/openrc-run

description="sing-box service"
command="/etc/sing-box/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF

    cat > /etc/init.d/argo << 'EOF'
#!/sbin/openrc-run

description="Cloudflare Tunnel"
command="/bin/sh"
command_args="-c '/etc/sing-box/argo tunnel --url http://localhost:8001 --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/sing-box/argo.log 2>&1'"
command_background=true
pidfile="/var/run/argo.pid"
EOF

    chmod +x /etc/init.d/sing-box
    chmod +x /etc/init.d/argo

    rc-update add sing-box default
    rc-update add argo default

}

get_info() {  
  clear
  server_ip=$(get_realip)

  isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')

  argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "${work_dir}/argo.log" | sed 's@https://@@')

  echo -e "${green}\nArgoDomain：${re}${purple}$argodomain${re}"

  yellow "\n温馨提醒：如节点不通，请打开V2rayN里的 “跳过证书验证”，或将节点的跳过证书验证设置为“true”\n"

  VMESS="{ \"v\": \"2\", \"ps\": \"${isp}\", \"add\": \"www.visa.com.tw\", \"port\": \"443\", \"id\": \"${uuid}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\", \"fp\": \"randomized\", \"allowlnsecure\": \"flase\"}"

  cat > ${work_dir}/url.txt <<EOF
vless://${uuid}@${server_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.zara.com&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${isp}

vmess://$(echo "$VMESS" | base64 -w0)

hysteria2://${uuid}@${server_ip}:${hy2_port}/?sni=www.bing.com&alpn=h3&insecure=1#${isp}

tuic://${uuid}:@${server_ip}:${tuic_port}?sni=www.bing.com&alpn=h3&insecure=1&congestion_control=bbr#${isp}

socks5://$socks_user:$socks_pass@${server_ip}:$socks_port#${isp}
EOF
echo ""
while IFS= read -r line; do echo -e "${purple}$line"; done < ${work_dir}/url.txt
base64 -w0 ${work_dir}/url.txt > ${work_dir}/sub.txt
echo ""
green "节点订阅链接：http://${server_ip}/${password}\n\n订阅链接适用于V2rayN,Nekbox,Sterisand,Loon,小火箭,圈X等\n"
$work_dir/qrencode "http://${server_ip}/${password}"
echo ""
}

# 修复nginx因host无法安装的问题
fix_nginx() {
    HOSTNAME=$(hostname)
    NGINX_CONFIG_FILE="/etc/nginx/nginx.conf"
    grep -q "127.0.1.1 $HOSTNAME" /etc/hosts || echo "127.0.1.1 $HOSTNAME" | tee -a /etc/hosts >/dev/null
    id -u nginx >/dev/null 2>&1 || useradd -r -d /var/www -s /sbin/nologin nginx >/dev/null 2>&1
    grep -q "^user nginx;" $NGINX_CONFIG_FILE || sed -i "s/^user .*/user nginx;/" $NGINX_CONFIG_FILE >/dev/null 2>&1
}

# nginx订阅配置
add_nginx_conf() {
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    cat > /etc/nginx/nginx.conf << EOF
# nginx_conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    server {
      listen 80;
      listen [::]:80;

    location /$password {
      alias /etc/sing-box/sub.txt;
      default_type 'text/plain; charset=utf-8';
    }
  }
}
EOF

nginx -t

if [ $? -eq 0 ]; then
    if [ -f /etc/alpine-release ]; then
    	touch /run/nginx.pid
     	pkill -f '[n]ginx'
        nginx -s reload
        rc-service nginx restart
    else
        rm /run/nginx.pid
        systemctl daemon-reload
        systemctl restart nginx
    fi
fi
}

# 启动 sing-box
start_singbox() {
if [ ${check_singbox} -eq 1 ]; then
    yellow "正在启动 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service sing-box start
    else
        systemctl daemon-reload
        systemctl start "${server_name}"
    fi
   if [ $? -eq 0 ]; then
       green "${server_name} 服务已成功启动\n"
   else
       red "${server_name} 服务启动失败\n"
   fi
elif [ ${check_singbox} -eq 0 ]; then
    yellow "sing-box 正在运行\n"
    sleep 1
    menu
else
    yellow "sing-box 尚未安装!\n"
    sleep 1
    menu
fi
}

# 停止 sing-box
stop_singbox() {
if [ ${check_singbox} -eq 0 ]; then
   yellow "正在停止 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service sing-box stop
    else
        systemctl stop "${server_name}"
    fi
   if [ $? -eq 0 ]; then
       green "${server_name} 服务已成功停止\n"
   else
       red "${server_name} 服务停止失败\n"
   fi

elif [ ${check_singbox} -eq 1 ]; then
    yellow "sing-box 未运行\n"
    sleep 1
    menu
else
    yellow "sing-box 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 sing-box
restart_singbox() {
if [ ${check_singbox} -eq 0 ]; then
   yellow "正在重启 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service ${server_name} restart
    else
        systemctl daemon-reload
        systemctl restart "${server_name}"
    fi
    if [ $? -eq 0 ]; then
        green "${server_name} 服务已成功重启\n"
    else
        red "${server_name} 服务重启失败\n"
    fi
elif [ ${check_singbox} -eq 1 ]; then
    yellow "sing-box 未运行\n"
    sleep 1
    menu
else
    yellow "sing-box 尚未安装！\n"
    sleep 1
    menu
fi
}

# 启动 argo
start_argo() {
if [ ${check_argo} -eq 1 ]; then
    yellow "正在启动 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service argo start
    else
        systemctl daemon-reload
        systemctl start argo
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 0 ]; then
    green "Argo 服务正在运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 停止 argo
stop_argo() {
if [ ${check_argo} -eq 0 ]; then
    yellow "正在停止 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service stop start
    else
        systemctl daemon-reload
        systemctl stop argo
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功停止\n"
    else
        red "Argo 服务停止失败\n"
    fi
elif [ ${check_argo} -eq 1 ]; then
    yellow "Argo 服务未运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 argo
restart_argo() {
if [ ${check_argo} -eq 0 ]; then
    yellow "正在重启 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service argo restart
    else
        systemctl daemon-reload
        systemctl restart argo
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 1 ]; then
    yellow "Argo 服务未运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}

# 启动 nginx
start_nginx() {
if command -v nginx &>/dev/null; then
    yellow "正在启动 nginx 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service nginx start
    else
        systemctl daemon-reload
        systemctl start nginx
    fi
    if [ $? -eq 0 ]; then
        green "Nginx 服务已成功启动\n"
    else
        red "Nginx 启动失败\n"
    fi
else
    yellow "Nginx 尚未安装！\n"
    sleep 1
    menu
fi
}

# 重启 nginx
restart_nginx() {
if command -v nginx &>/dev/null; then
    yellow "正在重启 nginx 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service nginx restart
    else
        systemctl restart nginx
    fi
    if [ $? -eq 0 ]; then
        green "Nginx 服务已成功重启\n"
    else
        red "Nginx 重启失败\n"
    fi
else
    yellow "Nginx 尚未安装！\n"
    sleep 1
    menu
fi
}

# 卸载 sing-box
uninstall_singbox() {
   reading "确定要卸载 sing-box 吗? (y/n): " choice
   case "${choice}" in
       y|Y)
           yellow "正在卸载 sing-box"
           if [ -f /etc/alpine-release ]; then
                rc-service sing-box stop
                rc-service argo stop
                rm /etc/init.d/sing-box /etc/init.d/argo
                rc-update del sing-box default
                rc-update del argo default
           else
                # 停止 sing-box和 argo 服务
                systemctl stop "${server_name}"
                systemctl stop argo
                # 禁用 sing-box 服务
                systemctl disable "${server_name}"
                systemctl disable argo

                # 重新加载 systemd
                systemctl daemon-reload || true
            fi
           # 删除配置文件和日志
           rm -rf "${work_dir}" || true
           rm -f "${log_dir}" || true
           
           # 卸载Nginx
           reading "\n是否卸载 Nginx？${green}(卸载请输入 ${yellow}y${re} ${green}回车将跳过卸载Nginx) (y/n): ${re}" choice
            case "${choice}" in
                y|Y)
                    manage_packages uninstall nginx
                    ;;
                 *)
                    yellow "取消卸载Nginx\n"
                    ;;
            esac

            green "\nsing-box 卸载成功\n"
           ;;
       *)
           purple "已取消卸载操作\n"
           ;;
   esac
}

# 创建快捷指令
create_shortcut() {
  cat > "$work_dir/sb.sh" << EOF
#!/usr/bin/env bash

bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh) \$1
EOF
  chmod +x "$work_dir/sb.sh"
  ln -sf "$work_dir/sb.sh" /usr/bin/sb
  if [ -s /usr/bin/sb ]; then
    green "\nsb 快捷指令创建成功\n"
  else
    red "\nsb 快捷指令创建失败\n"
  fi
}

# 适配alpine运行argo报错用户组和dns的问题
change_hosts() {
    sh -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    sed -i '1s/.*/127.0.0.1   localhost/' /etc/hosts
    sed -i '2s/.*/::1         localhost/' /etc/hosts
}

# 变更配置
change_config() {
if [ ${check_singbox} -eq 0 ]; then
    clear
    echo ""
    green "1. 修改端口"
    skyblue "------------"
    green "2. 修改UUID"
    skyblue "------------"
    green "3. 修改Reality伪装域名"
    skyblue "------------"
    purple "${purple}4. 返回主菜单"
    skyblue "------------"
    reading "请输入选择: " choice
    case "${choice}" in
        1)
            echo ""
            green "1. 修改vless-reality端口"
            skyblue "------------"
            green "2. 修改hysteria2端口"
            skyblue "------------"
            green "3. 修改tuic端口"
            skyblue "------------"
            green "4. 修改socks端口"
            skyblue "------------"
            purple "5. 返回上一级菜单"
            skyblue "------------"
            reading "请输入选择: " choice
            case "${choice}" in
                1)
                    reading "\n请输入vless-reality端口 (回车跳过将使用随机端口): " new_port
                    [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
                    sed -i '/"type": "vless"/,/listen_port/ s/"listen_port": [0-9]\+/"listen_port": '"$new_port"'/' $config_dir
                    restart_singbox
                    sed -i 's/\(vless:\/\/[^@]*@[^:]*:\)[0-9]\{1,\}/\1'"$new_port"'/' $client_dir
                    base64 -w0 /etc/sing-box/url.txt > /etc/sing-box/sub.txt
                    while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                    green "\nvless-reality端口已修改成：${purple}$new_port${re} ${green}请更新订阅或手动更改vless-reality端口${re}\n"
                    ;;
                2)
                    reading "\n请输入hysteria2端口 (回车跳过将使用随机端口): " new_port
                    [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
                    sed -i '/"type": "hysteria2"/,/listen_port/ s/"listen_port": [0-9]\+/"listen_port": '"$new_port"'/' $config_dir
                    restart_singbox
                    sed -i 's/\(hysteria2:\/\/[^@]*@[^:]*:\)[0-9]\{1,\}/\1'"$new_port"'/' $client_dir
                    base64 -w0 $client_dir > /etc/sing-box/sub.txt
                    while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                    green "\nhysteria2端口已修改为：${purple}${new_port}${re} ${green}请更新订阅或手动更改hysteria2端口${re}\n"
                    ;;
                3)
                    reading "\n请输入tuic端口 (回车跳过将使用随机端口): " new_port
                    [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
                    sed -i '/"type": "tuic"/,/listen_port/ s/"listen_port": [0-9]\+/"listen_port": '"$new_port"'/' $config_dir
                    restart_singbox
                    sed -i 's/\(tuic:\/\/[^@]*@[^:]*:\)[0-9]\{1,\}/\1'"$new_port"'/' $client_dir
                    base64 -w0 $client_dir > /etc/sing-box/sub.txt
                    while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                    green "\ntuic端口已修改为：${purple}${new_port}${re} ${green}请更新订阅或手动更改tuic端口${re}\n"
                    ;;
                4)
                    reading "\n请输入socks端口 (回车跳过将使用随机端口): " new_port
                    [ -z "$new_port" ] && new_port=$(shuf -i 2000-65000 -n 1)
                    sed -i '/"type": "socks"/,/listen_port/ s/"listen_port": [0-9]\+/"listen_port": '"$new_port"'/' $config_dir
                    restart_singbox
                    sed -i 's/\(socks5:\/\/[^@]*@[^:]*:\)[0-9]\{1,\}/\1'"$new_port"'/' $client_dir
                    base64 -w0 $client_dir > /etc/sing-box/sub.txt
                    while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                    green "\nsocks端口已修改为：${purple}${new_port}${re} ${green}请更新订阅或手动更改socks端口${re}\n"
                    ;;
                5)  change_config ;;
                *)  red "无效的选项，请输入 1 到 5" ;;
            esac
            ;;
        2)
            reading "\n请输入新的UUID: " new_uuid
            [ -z "$new_uuid" ] && new_uuid=$(cat /proc/sys/kernel/random/uuid)
            sed -i -E '
                s/"uuid": "([a-f0-9-]+)"/"uuid": "'"$new_uuid"'"/g;
                s/"uuid": "([a-f0-9-]+)"$/\"uuid\": \"'$new_uuid'\"/g;
                s/"password": "([a-f0-9-]+)"/"password": "'"$new_uuid"'"/g
            ' $config_dir

            restart_singbox
            sed -i -E 's/(vless:\/\/|hysteria2:\/\/)[^@]*(@.*)/\1'"$new_uuid"'\2/' $client_dir
            sed -i "s/tuic:\/\/[0-9a-f\-]\{36\}/tuic:\/\/$new_uuid/" /etc/sing-box/url.txt
            isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
            argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "${work_dir}/argo.log" | sed 's@https://@@')
            VMESS="{ \"v\": \"2\", \"ps\": \"${isp}\", \"add\": \"www.visa.com.sg\", \"port\": \"443\", \"id\": \"${new_uuid}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\", \"fp\": \"randomized\", \"allowlnsecure\": \"flase\"}"
            encoded_vmess=$(echo "$VMESS" | base64 -w0)
            sed -i -E '/vmess:\/\//{s@vmess://.*@vmess://'"$encoded_vmess"'@}' $client_dir
            base64 -w0 $client_dir > /etc/sing-box/sub.txt
            while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
            green "\nUUID已修改为：${purple}${new_uuid}${re} ${green}请更新订阅或手动更改所有节点的UUID${re}\n"
            ;;
        3)  
            clear
            green "\n1. www.ups.com\n\n2. www.svix.com\n\n3. www.cboe.com\n\n4. www.hubspot.com\n"
            reading "\n请输入新的Reality伪装域名(可自定义输入,回车留空将使用默认1): " new_sni
                if [ -z "$new_sni" ]; then    
                    new_sni="www.ups.com"
                elif [[ "$new_sni" == "1" ]]; then
                    new_sni="www.ups.com"
                elif [[ "$new_sni" == "2" ]]; then
                    new_sni="www.svix.com"
                elif [[ "$new_sni" == "3" ]]; then
                    new_sni="www.cboe.com"
                elif [[ "$new_sni" == "4" ]]; then
                    new_sni="www.hubspot.com"
                else
                    new_sni="$new_sni"
                fi
                jq --arg new_sni "$new_sni" '
                (.inbounds[] | select(.type == "vless") | .tls.server_name) = $new_sni |
                (.inbounds[] | select(.type == "vless") | .tls.reality.handshake.server) = $new_sni
                ' "$config_dir" > "$config_file.tmp" && mv "$config_file.tmp" "$config_dir"
                restart_singbox
                sed -i "s/\(vless:\/\/[^\?]*\?\([^\&]*\&\)*sni=\)[^&]*/\1$new_sni/" $client_dir
                base64 -w0 $client_dir > /etc/sing-box/sub.txt
                while IFS= read -r line; do yellow "$line"; done < ${work_dir}/url.txt
                echo ""
                green "\nReality sni已修改为：${purple}${new_sni}${re} ${green}请更新订阅或手动更改reality节点的sni域名${re}\n"
            ;; 
        4)  menu ;;
        *)  read "无效的选项！" ;; 
    esac
else
    yellow "sing-box 尚未安装！"
    sleep 1
    menu
fi
}

disable_open_sub() {
if [ ${check_singbox} -eq 0 ]; then
    clear
    echo ""
    green "1. 关闭节点订阅"
    skyblue "------------"
    green "2. 开启节点订阅"
    skyblue "------------"
    green "3. 更换订阅端口"
    skyblue "------------"
    purple "4. 返回主菜单"
    skyblue "------------"
    reading "请输入选择: " choice
    case "${choice}" in
        1)
            if command -v nginx &>/dev/null; then
                if [ -f /etc/alpine-release ]; then
                    rc-service nginx status | grep -q "started" && rc-service nginx stop || red "nginx not running"
                else 
                    [ "$(systemctl is-active nginx)" = "active" ] && systemctl stop nginx || red "ngixn not running"
                fi
            else
                yellow "Nginx is not installed"
            fi

            green "\n已关闭节点订阅\n"     
            ;; 
        2)
            green "\n已开启节点订阅\n"
            server_ip=$(get_realip)
            password=$(tr -dc A-Za-z < /dev/urandom | head -c 32) 
            sed -i -E "s/(location \/)[^ ]+/\1${password//\//\\/}/" /etc/nginx/nginx.conf
	    sub_port=$(port=$(grep -E 'listen [0-9]+;' /etc/nginx/nginx.conf | awk '{print $2}' | sed 's/;//'); if [ "$port" -eq 80 ]; then echo ""; else echo "$port"; fi)
            start_nginx
            (port=$(grep -E 'listen [0-9]+;' /etc/nginx/nginx.conf | awk '{print $2}' | sed 's/;//'); if [ "$port" -eq 80 ]; then echo ""; else green "订阅端口：$port"; fi); link=$(if [ -z "$sub_port" ]; then echo "http://$server_ip/$password"; else echo "http://$server_ip:$sub_port/$password"; fi); green "\n新的节点订阅链接：$link\n"
            ;; 

        3)
            reading "请输入新的订阅端口(1-65535):" sub_port
            [ -z "$sub_port" ] && sub_port=$(shuf -i 2000-65000 -n 1)
            until [[ -z $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$sub_port") ]]; do
                if [[ -n $(netstat -tuln | grep -w tcp | awk '{print $4}' | sed 's/.*://g' | grep -w "$sub_port") ]]; then
                    echo -e "${red}${new_port}端口已经被其他程序占用，请更换端口重试${re}"
                    reading "请输入新的订阅端口(1-65535):" sub_port
                    [[ -z $sub_port ]] && sub_port=$(shuf -i 2000-65000 -n 1)
                fi
            done
            sed -i 's/listen [0-9]\+;/listen '$sub_port';/g' /etc/nginx/nginx.conf
            path=$(sed -n 's/.*location \/\([^ ]*\).*/\1/p' /etc/nginx/nginx.conf)
            server_ip=$(get_realip)
            restart_nginx
            green "\n订阅端口更换成功\n"
            green "新的订阅链接为：http://$server_ip:$sub_port/$path\n"
            ;; 
        4)  menu ;; 
        *)  red "无效的选项！" ;;
    esac
else
    yellow "sing-box 尚未安装！"
    sleep 1
    menu
fi
}

# singbox 管理
manage_singbox() {
    green "1. 启动sing-box服务"
    skyblue "-------------------"
    green "2. 停止sing-box服务"
    skyblue "-------------------"
    green "3. 重启sing-box服务"
    skyblue "-------------------"
    purple "4. 返回主菜单"
    skyblue "------------"
    reading "\n请输入选择: " choice
    case "${choice}" in
        1) start_singbox ;;  
        2) stop_singbox ;;
        3) restart_singbox ;;
        4) menu ;;
        *) red "无效的选项！" ;;
    esac
}

# Argo 管理
manage_argo() {
if [ ${check_argo} -eq 2 ]; then
    yellow "Argo 尚未安装！"
    sleep 1
    menu
else
    clear
    echo ""
    green "1. 启动Argo服务"
    skyblue "------------"
    green "2. 停止Argo服务"
    skyblue "------------"
    green "3. 重启Argo服务"
    skyblue "------------"
    green "4. 添加Argo固定隧道"
    skyblue "----------------"
    green "5. 切换回Argo临时隧道"
    skyblue "------------------"
    green "6. 重新获取Argo临时域名"
    skyblue "-------------------"
    purple "7. 返回主菜单"
    skyblue "-----------"
    reading "\n请输入选择: " choice
    case "${choice}" in
        1)  start_argo ;;
        2)  stop_argo ;; 
        3)  restart_argo ;; 
        4)
            clear
            yellow "\n固定隧道可为json或token，固定隧道端口为8001，自行在cf后台设置\n\njson在f佬维护的站点里获取，获取地址：${purple}https://fscarmen.cloudflare.now.cc${re}\n"
            reading "\n请输入你的argo域名: " argo_domain
            ArgoDomain=$argo_domain
            reading "\n请输入你的argo密钥(token或json): " argo_auth
            if [[ $argo_auth =~ TunnelSecret ]]; then
                echo $argo_auth > ${work_dir}/tunnel.json
                cat > ${work_dir}/tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$argo_auth")
credentials-file: ${work_dir}/tunnel.json
protocol: http2
                                           
ingress:
  - hostname: $ArgoDomain
    service: http://localhost:8001
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

                sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --edge-ip-version auto --config /etc/sing-box/tunnel.yml run 2>&1"' /etc/systemd/system/argo.service
                restart_argo
                sleep 1 
                change_argo_domain

            elif [[ $argo_auth =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
                sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token '$argo_auth' 2>&1"' /etc/systemd/system/argo.service
                restart_argo
                sleep 1 
                change_argo_domain
            else
                yellow "你输入的argo域名或token不匹配，请重新输入"
                manage_argo
            fi
            ;; 
        5)
            clear
            if [ -f /etc/alpine-release ]; then
                alpine_openrc_services
            else
                main_systemd_services
            fi
            get_quick_tunnel
            change_argo_domain 
            ;; 

        6)  
            if [ -f /etc/alpine-release ]; then
                if grep -q '--url http://localhost:8001' /etc/init.d/argo; then
                    get_quick_tunnel
                    change_argo_domain 
                else
                    yellow "当前使用固定隧道，无法获取临时隧道"
                    sleep 2
                    menu
                fi
            else
                if grep -q 'ExecStart=.*--url http://localhost:8001' /etc/systemd/system/argo.service; then
                    get_quick_tunnel
                    change_argo_domain 
                else
                    yellow "当前使用固定隧道，无法获取临时隧道"
                    sleep 2
                    menu
                fi
            fi 
            ;; 
        7)  menu ;; 
        *)  red "无效的选项！" ;;
    esac
fi
}

# 获取argo临时隧道
get_quick_tunnel() {
restart_argo
yellow "获取临时argo域名中，请稍等...\n"
sleep 4
get_argodomain=$(grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "${work_dir}/argo.log" | sed 's@https://@@')
green "ArgoDomain：${purple}$get_argodomain${re}"
ArgoDomain=$get_argodomain
}

# 更新Argo域名到订阅
change_argo_domain() {
content=$(cat "$client_dir")
vmess_url=$(grep -o 'vmess://[^ ]*' "$client_dir")
vmess_prefix="vmess://"
encoded_vmess="${vmess_url#"$vmess_prefix"}"
decoded_vmess=$(echo "$encoded_vmess" | base64 --decode)
updated_vmess=$(echo "$decoded_vmess" | jq --arg new_domain "$ArgoDomain" '.host = $new_domain | .sni = $new_domain')
encoded_updated_vmess=$(echo "$updated_vmess" | base64 | tr -d '\n')
new_vmess_url="$vmess_prefix$encoded_updated_vmess"
new_content=$(echo "$content" | sed "s|$vmess_url|$new_vmess_url|")
echo "$new_content" > "$client_dir"
base64 -w0 ${work_dir}/url.txt > ${work_dir}/sub.txt
green "\nvmess节点已更新,更新订阅或手动复制以下vmess-argo节点\n"
purple "$new_vmess_url\n" 
}

# 查看节点信息和订阅链接
check_nodes() {
if [ ${check_singbox} -eq 0 ]; then
    while IFS= read -r line; do purple "${purple}$line"; done < ${work_dir}/url.txt
    echo ""
    server_ip=$(get_realip)
    lujing=$(grep -oP 'location /\K[^ ]+' "/etc/nginx/nginx.conf")
    green "\n节点订阅链接：http://${server_ip}/${lujing}\n"
else 
    yellow "sing-box 尚未安装或未运行,请先安装或启动sing-box"
    sleep 1
    menu
fi
}

# 主菜单
menu() {
   check_singbox &>/dev/null; check_singbox=$?
   check_nginx &>/dev/null; check_nginx=$?
   check_argo &>/dev/null; check_argo=$?
   check_singbox_status=$(check_singbox)
   check_nginx_status=$(check_nginx)
   check_argo_status=$(check_argo)
   clear
   echo ""
   purple "=== 老王sing-box一键安装脚本 ===\n"
   purple "---Argo 状态: ${check_argo_status}"   
   purple "--Nginx 状态: ${check_nginx_status}"
   purple "singbox 状态: ${check_singbox_status}\n"
   green "1. 安装sing-box"
   red "2. 卸载sing-box"
   echo "==============="
   green "3. sing-box管理"
   green "4. Argo隧道管理"
   echo  "==============="
   green  "5. 查看节点信息"
   green  "6. 修改节点配置"
   green  "7. 管理节点订阅"
   echo  "==============="
   purple "8. ssh综合工具箱"
   echo  "==============="
   red "0. 退出脚本"
   echo "==========="
   reading "请输入选择(0-8): " choice
   echo ""
}

# 捕获 Ctrl+C 信号
trap 'red "已取消操作"; exit' INT

# 主循环
while true; do
   menu
   case "${choice}" in
        1)  
            if [ ${check_singbox} -eq 0 ]; then
                yellow "sing-box 已经安装！"
            else
                fix_nginx
                manage_packages install nginx jq tar iptables openssl coreutils
                install_singbox

                if [ -x "$(command -v systemctl)" ]; then
                    main_systemd_services
                elif [ -x "$(command -v rc-update)" ]; then
                    alpine_openrc_services
                    change_hosts
                    rc-service sing-box restart
                    rc-service argo restart
                else
                    echo "Unsupported init system"
                    exit 1 
                fi

                sleep 4
                get_info
                add_nginx_conf
                create_shortcut
            fi
           ;;
        2) uninstall_singbox ;;
        3) manage_singbox ;;
        4) manage_argo ;;
        5) check_nodes ;;
        6) change_config ;;
        7) disable_open_sub ;;
        8) 
           clear
           curl -fsSL https://raw.githubusercontent.com/eooce/ssh_tool/main/ssh_tool.sh -o ssh_tool.sh && chmod +x ssh_tool.sh && ./ssh_tool.sh
           ;;           
        0) exit 0 ;;
        *) red "无效的选项，请输入 0 到 8" ;; 
   esac
   read -n 1 -s -r -p $'\033[1;91m按任意键继续...\033[0m'
done
