import socket
import struct
import time
import sys

# =============================================================================
# 網路與目標設定 (動態快取邏輯)
# =============================================================================
MASTER_HOSTNAME = "eclypse-master.local"
PORT = 5000
_CACHED_IP = None  # 用於存放解析後的實體 IP

def _get_master_ip():
    """內部函式：解析並快取 Master 的 IP，避開每次連線的 DNS 延遲"""
    global _CACHED_IP
    if _CACHED_IP:
        return _CACHED_IP
    
    print(f"[*] 正在搜尋叢集閘道 {MASTER_HOSTNAME} ...")
    try:
        # 第一次解析可能耗時 5-10 秒，但僅此一次
        _CACHED_IP = socket.gethostbyname(MASTER_HOSTNAME)
        print(f"[✔] 成功定位 IP: {_CACHED_IP}\n")
        return _CACHED_IP
    except Exception as e:
        print(f"[X] 無法解析主機名稱。請確認板子已連網。")
        sys.exit(1)

def send_awg_command(target_name, cmd, n_points=0, data=b""):
    """發送封包並提供高精度分段計時 (供 play_waves.py 使用)"""
    master_ip = _get_master_ip()
    
    try:
        t_total_start = time.perf_counter()

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1) # 禁用 Nagle
            s.settimeout(10.0)
            
            # --- 1. 偵測 TCP 連線耗時 (使用 IP 後應 < 5ms) ---
            t0 = time.perf_counter()
            s.connect((master_ip, PORT))
            t1 = time.perf_counter()
            conn_ms = (t1 - t0) * 1000
            
            # --- 2. 封包準備 ---
            name_bytes = target_name.encode('ascii').ljust(16, b'\x00')
            cmd_byte = cmd.encode('ascii')
            len_bytes = struct.pack("<I", n_points)
            header = name_bytes + cmd_byte + len_bytes
            
            # --- 3. 偵測資料發送耗時 ---
            t2 = time.perf_counter()
            s.sendall(header + data)
            t3 = time.perf_counter()
            send_ms = (t3 - t2) * 1000
            
            # --- 4. 偵測硬體執行回報 (Master 處理指令的時間) ---
            t4 = time.perf_counter()
            response = s.recv(1024).decode('ascii')
            t5 = time.perf_counter()
            proc_ms = (t5 - t4) * 1000

        total_ms = (time.perf_counter() - t_total_start) * 1000

        # --- 列印診斷數據 ---
        print(f"[*] 目的地: {target_name} | 指令: {cmd}")
        print(f"    ├─ 建立連線 (IP Cache): {conn_ms:8.2f} ms")
        print(f"    ├─ 資料發送耗時:      {send_ms:8.2f} ms")
        print(f"    └─ 硬體處理回報:      {proc_ms:8.2f} ms")
        print(f"[✔] 總體執行延遲:        {total_ms:8.2f} ms | 回報: {response}\n")
        
        return response
            
    except Exception as e:
        print(f"[X] 通訊失敗: {e}\n")

# --- 保留並強化原本的其他函式 ---

def set_remote_clock(target_name, mode):
    """設定時鐘模式，同樣保留時間偵測"""
    return send_awg_command(target_name, 'C', n_points=mode)

def update_remote_calibration(target_name, ch_idx, mult, add):
    """發送校正指令，同樣保留時間偵測"""
    payload = struct.pack("<II", mult, add)
    return send_awg_command(target_name, 'K', n_points=ch_idx, data=payload)