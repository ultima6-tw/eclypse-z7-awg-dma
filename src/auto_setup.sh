#!/bin/bash

# --- 0. 權限檢查 ---
[ "$EUID" -ne 0 ] && echo "請使用 sudo 執行！" && exit 1

# --- 1. 基礎設定 ---
CURRENT_HOSTNAME=$(hostname)
IFACE=$(ls /sys/class/net | grep -v lo | head -n 1)
echo "[*] 正在初始化網路介面：$IFACE"

# --- 2. 部署網路設定檔 (關鍵順序) ---
cat > /etc/nsswitch.conf << EOF
passwd:         compat
group:          compat
shadow:         compat
hosts:          files resolve [!UNAVAIL=return] dns
networks:       files
protocols:      db files
services:       db files
ethers:         db files
rpc:            db files
netgroup:       nis
EOF

mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-ethernet.network << EOF
[Match]
Name=$IFACE
[Network]
DHCP=ipv4
MulticastDNS=yes
EOF

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nMulticastDNS=yes" > /etc/systemd/resolved.conf.d/mdns.conf

# 重啟網路引擎
systemctl restart systemd-networkd
sleep 2
systemctl restart systemd-resolved
sleep 2

# --- 3. 智慧角色偵測與動態註冊機制 ---
echo "[*] 正在探查網路角色..."
IS_MASTER_ALIVE=$(ping -c 1 -W 2 eclypse-master.local 2>/dev/null)

if [ "$CURRENT_HOSTNAME" == "eclypse-master" ] || [ -z "$IS_MASTER_ALIVE" ]; then
    HOST_NAME="eclypse-master"
    MAC_ADDR="00:0a:35:00:00:01"
    
    # Master 強制生成金鑰邏輯
    SSH_DIR="/home/petalinux/.ssh"
    mkdir -p "$SSH_DIR"
    chown petalinux:petalinux "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    if [ ! -f "$SSH_DIR/id_rsa" ]; then
        sudo -u petalinux ssh-keygen -t rsa -N "" -f "$SSH_DIR/id_rsa"
        chown petalinux:petalinux "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
    fi

    # ====================================================================
    # 動態生成：具備「註冊 Slave (IP + Hostname)」功能的專屬金鑰伺服器
    # ====================================================================
    cat > "$SSH_DIR/key_server.py" << 'EOF_PY'
import http.server
import socketserver
import os

PORT = 8000
REGISTRY_FILE = "/home/petalinux/active_slaves.txt"

class RegistryHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        client_ip = self.client_address[0]
        hostname = "unknown"
        
        # 擷取 URL 中的 hostname 參數
        if "?name=" in self.path:
            hostname = self.path.split("?name=")[1].split("&")[0]
            
        registered_lines = []
        if os.path.exists(REGISTRY_FILE):
            with open(REGISTRY_FILE, "r") as f:
                registered_lines = f.read().splitlines()
                
        # 檢查是否已存在，若存在則更新 IP，若不存在則新增
        updated = False
        new_lines = []
        for line in registered_lines:
            if line.endswith(f" {hostname}"):
                new_lines.append(f"{client_ip} {hostname}")
                updated = True
            else:
                new_lines.append(line)
                
        if not updated:
            new_lines.append(f"{client_ip} {hostname}")
            
        with open(REGISTRY_FILE, "w") as f:
            f.write("\n".join(new_lines) + "\n")
            
        return super().do_GET()

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), RegistryHandler) as httpd:
    httpd.serve_forever()
EOF_PY

    chown petalinux:petalinux "$SSH_DIR/key_server.py"

    cat > /etc/systemd/system/ssh-key-server.service << EOF
[Unit]
Description=Master SSH Public Key & Registry Server
After=network.target
[Service]
Type=simple
User=petalinux
WorkingDirectory=$SSH_DIR
ExecStart=/usr/bin/python3 $SSH_DIR/key_server.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ssh-key-server.service
    systemctl restart ssh-key-server.service
    echo "[+] Master 設定完成，金鑰伺服器與動態註冊機制已啟動。"

else
    # Slave 自動排號邏輯
    SLAVE_ID=1
    while ping -c 1 -W 1 "eclypse-slave${SLAVE_ID}.local" > /dev/null 2>&1; do
        let SLAVE_ID=SLAVE_ID+1
    done
    HOST_NAME="eclypse-slave${SLAVE_ID}"
    MAC_TAIL=$(printf "%02d" $((SLAVE_ID + 1)))
    MAC_ADDR="00:0a:35:00:00:${MAC_TAIL}"

    # Slave 領取公鑰，並主動報上自己的 HOST_NAME
    mkdir -p /home/petalinux/.ssh
    for i in {1..20}; do
        # 【修改這裡】URL 加上 ?name 參數
        if wget -q "http://eclypse-master.local:8000/id_rsa.pub?name=${HOST_NAME}" -O /tmp/master_key.pub; then
            cat /tmp/master_key.pub >> /home/petalinux/.ssh/authorized_keys
            sort -u /home/petalinux/.ssh/authorized_keys -o /home/petalinux/.ssh/authorized_keys
            chown -R petalinux:petalinux /home/petalinux/.ssh
            chmod 600 /home/petalinux/.ssh/authorized_keys
            echo "[+] SSH 授權成功，已同時向 Master 完成註冊。"
            break
        fi
        sleep 5
    done
fi

# --- 4. 權限與環境配置 ---
hostnamectl set-hostname $HOST_NAME
cat > /etc/systemd/network/10-mac.link << EOF
[Match]
OriginalName=$IFACE
[Link]
MACAddress=$MAC_ADDR
EOF

echo "petalinux ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/petalinux-nopasswd
chmod 0440 /etc/sudoers.d/petalinux-nopasswd

BASHRC="/home/petalinux/.bashrc"
grep -q "alias python3=" "$BASHRC" || echo "alias python3='sudo /usr/bin/python3'" >> "$BASHRC"

echo -e "Host *.local\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null" > /home/petalinux/.ssh/config
chown -R petalinux:petalinux /home/petalinux/.ssh

# --- 5. 部署 AWG 背景服務 (Daemon) ---
echo "[*] 正在部署 AWG 分散式控制伺服器..."

cat > /etc/systemd/system/awg.service << EOF
[Unit]
Description=AWG Distributed Control Daemon
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/home/petalinux
ExecStart=/usr/bin/python3 -u /home/petalinux/awg_daemon.py
Restart=always
TimeoutStopSec=5
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable awg.service
echo "[+] AWG 服務設定完成，將於重啟後自動常駐。"

# --- 6. 完工重啟 ---
echo "[!] $HOST_NAME 初始化完畢，3秒後重啟..."
sleep 3
reboot