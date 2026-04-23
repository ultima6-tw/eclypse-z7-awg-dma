#!/bin/bash

# --- 0. Permission check ---
[ "$EUID" -ne 0 ] && echo "Please run with sudo!" && exit 1

# --- 1. Basic setup ---
CURRENT_HOSTNAME=$(hostname)
IFACE=$(ls /sys/class/net | grep -v lo | head -n 1)
echo "[*] Initializing network interface: $IFACE"

# --- 2. Deploy network configuration ---
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
LinkLocalAddressing=yes
MulticastDNS=yes
[DHCP]
Timeout=5
EOF

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nMulticastDNS=yes" > /etc/systemd/resolved.conf.d/mdns.conf

# Restart network stack
systemctl restart systemd-networkd
sleep 2
systemctl restart systemd-resolved
sleep 2

# --- 3. Role detection and dynamic registration ---
echo "[*] Detecting network role..."
IS_MASTER_ALIVE=$(ping -c 1 -W 2 eclypse-master.local 2>/dev/null)

if [ "$CURRENT_HOSTNAME" == "eclypse-master" ] || [ -z "$IS_MASTER_ALIVE" ]; then
    HOST_NAME="eclypse-master"
    MAC_ADDR="00:0a:35:00:00:01"

    # Master: generate SSH keypair
    SSH_DIR="/home/petalinux/.ssh"
    mkdir -p "$SSH_DIR"
    chown petalinux:petalinux "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    if [ ! -f "$SSH_DIR/id_rsa" ]; then
        sudo -u petalinux ssh-keygen -t rsa -N "" -f "$SSH_DIR/id_rsa"
        chown petalinux:petalinux "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub"
    fi

    # Deploy key server with slave registration support
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

        if "?name=" in self.path:
            hostname = self.path.split("?name=")[1].split("&")[0]

        registered_lines = []
        if os.path.exists(REGISTRY_FILE):
            with open(REGISTRY_FILE, "r") as f:
                registered_lines = f.read().splitlines()

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
    echo "[+] Master configured. Key server and registry service started."

else
    # Slave: auto-assign slave ID
    SLAVE_ID=1
    while ping -c 1 -W 1 "eclypse-slave${SLAVE_ID}.local" > /dev/null 2>&1; do
        let SLAVE_ID=SLAVE_ID+1
    done
    HOST_NAME="eclypse-slave${SLAVE_ID}"
    MAC_TAIL=$(printf "%02d" $((SLAVE_ID + 1)))
    MAC_ADDR="00:0a:35:00:00:${MAC_TAIL}"

    # Slave: fetch master public key and register hostname
    mkdir -p /home/petalinux/.ssh
    for i in {1..20}; do
        if wget -q "http://eclypse-master.local:8000/id_rsa.pub?name=${HOST_NAME}" -O /tmp/master_key.pub; then
            cat /tmp/master_key.pub >> /home/petalinux/.ssh/authorized_keys
            sort -u /home/petalinux/.ssh/authorized_keys -o /home/petalinux/.ssh/authorized_keys
            chown -R petalinux:petalinux /home/petalinux/.ssh
            chmod 600 /home/petalinux/.ssh/authorized_keys
            echo "[+] SSH authorized. Registered with master as ${HOST_NAME}."
            break
        fi
        sleep 5
    done
fi

# --- 4. Permissions and environment ---
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

# --- 5. Deploy AWG daemon service ---
echo "[*] Deploying AWG distributed control daemon..."

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
echo "[+] AWG service configured. Will start automatically on boot."

# --- 6. Done, reboot ---
echo "[!] $HOST_NAME setup complete. Rebooting in 3 seconds..."
sleep 3
reboot
