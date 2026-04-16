# =============================================================================
# VERSION: 2026.04.11-V5.6.5_CLUSTER_SYNC_STOP_FULL_COMMENTED
# DESCRIPTION: 基於 V5.6.4 的終極叢集連動修正，並完整保留所有開發註解。
#
#   ★ Bug A 修正：Monitor PTR 推進邏輯錯誤造成播放序列跳過中間項目
#     QUEUE_PTR 重新定義為「目前已 arm 在背景 path 等待下次 P 播放的索引」。
#     Monitor 在偵測到 path 翻轉時：
#       - 此刻 active path 上正在播的剛好就是上一次 arm 的 (= 舊 PTR)
#       - arm 下一組 (PTR+1) 到新背景，並更新 PTR
#
#   ★ Bug B 修正：全零波形與 S 指令安全停止
#     S 指令會把 DMA 描述符指向預先寫好的全零波形，讓 DAC 輸出歸零。
#       1. init_hardware 結尾保留 SRAM 最後 64KB 寫入全零波形
#       2. 動態駐列的可用空間相對減少 (USABLE_DATA_POOL_SIZE)
#       3. S 指令清空駐列、把全零 arm 到兩個 path
#
#   ★ Bug C 修正：Ctrl+C 中斷時 Slave 無法歸零的問題 (V5.6.5 核心)
#     現在 Master 收到 'S' 指令時，會自動廣播給所有 Slave，
#     確保所有節點都武裝全零波形後，Master 才擊發最終 Trigger，達成全叢集完美同步 0V 輸出。
#     (並確保 M_TRIG_CTRL 閘門永遠開啟，讓 0V 訊號能順利打入 DAC)
#
#   ★ 保留修正：accept 變數名、SRAM 4KB 對齊、DMA/DESC 常駐映射、P 指令冷卻。
# =============================================================================

import mmap
import struct
import os
import time
import socket
import signal
import sys
import threading
import numpy as np
import json

# =============================================================================
# 全域變數與防護鎖
# =============================================================================
FD = None
RUNNING = True
MY_HOSTNAME = socket.gethostname().lower()
IS_MASTER = "master" in MY_HOSTNAME

HW_LOCK = threading.Lock()        # 硬體暫存器操作互斥鎖 (防止監視器與指令衝突)
REGISTRY_LOCK = threading.Lock()  # 動態名單檔案互斥鎖 (防止 DHCP 修復衝突)
QUEUE_LOCK = threading.Lock()     # 駐列指標與清單操作鎖

CALIB_FILE = "dac_calib.json" 
CLOCK_FILE = "clock_config.json"
SLAVES_REGISTRY_FILE = "/home/petalinux/active_slaves.txt"

# --- 常駐全域映射 (避免每次操作都重新 mmap 耗時) ---
M_PATH_CTRL = None
M_TRIG_CTRL = None
M_CLK_CTRL  = None
M_DMA  = [None, None, None, None]
M_DESC = [None, None, None, None]

# 系統 page size (用於 D 指令 4KB 邊界對齊)
PAGE_SIZE = 4096
PAGE_MASK = PAGE_SIZE - 1

# --- P 指令冷卻時間控制 ---
P_COOLDOWN_SEC = 0.010
LAST_P_TIME = 0.0

# --- Monitor 狀態 ---
MONITOR_LAST_PATH = -1

# =============================================================================
# 1. 記憶體佈局、駐列定義與極速操作常數
# =============================================================================
# SRAM 佈局 (256MB):
#   0x30000000 ~ 0x3FEEFFFF  : 動態波形資料池 (254.9 MB, USABLE)
#   0x3FEF0000 ~ 0x3FEFFFFF  : 全零波形保留區 (64 KB)
#   0x3FF00000 ~ 0x3FFFFFFF  : 描述符池 (1 MB)
SRAM_BASE        = 0x30000000
DATA_POOL_BASE   = SRAM_BASE
DATA_POOL_SIZE   = 255 * 1024 * 1024     # 255 MB

# [全零波形保留區]：放在資料池末端，避開描述符池
ZERO_WAVE_RESERVED_SIZE = 0x10000   # 64 KB
ZERO_WAVE_PHYS_A = DATA_POOL_BASE + DATA_POOL_SIZE - ZERO_WAVE_RESERVED_SIZE  # 0x3FEF0000
ZERO_WAVE_PHYS_B = ZERO_WAVE_PHYS_A + ZERO_WAVE_RESERVED_SIZE // 2            # 0x3FEF8000
ZERO_WAVE_LEN    = 4096   # 1024 個 32-bit DMA word，足夠 DMA burst
ZERO_WAVE_META   = (ZERO_WAVE_PHYS_A, ZERO_WAVE_PHYS_B, ZERO_WAVE_LEN)

# 動態駐列實際可用空間 (扣掉零波形保留區)
USABLE_DATA_POOL_SIZE = DATA_POOL_SIZE - ZERO_WAVE_RESERVED_SIZE

DESC_POOL_BASE   = SRAM_BASE + DATA_POOL_SIZE  # 0x3FF00000
DMA_BASES        = [0x40000000, 0x40010000, 0x40020000, 0x40030000]

# 重新定義 4 個 DMA 通道的描述符固定位址 (每個分配 64KB 空間以確保絕對安全)
DESC_ADDRS = [
    DESC_POOL_BASE + 0x00000, # Path 0 - DMA A (CH1&2)
    DESC_POOL_BASE + 0x10000, # Path 1 - DMA A (CH1&2)
    DESC_POOL_BASE + 0x20000, # Path 0 - DMA B (CH3&4)
    DESC_POOL_BASE + 0x30000  # Path 1 - DMA B (CH3&4)
]
DESC_REGION_SIZE = 0x10000

# --- 駐列管理變數 ---
WAVE_QUEUE = []        # 存放格式: (phys_addr_a, phys_addr_b, length)
MAX_QUEUE_SIZE = 16
# QUEUE_PTR = 「目前已 arm 在背景 path 上、等待下次 P 切過去播的索引」
# - D 初始化 arm idx 0 到 bg 後，PTR = 0
# - 每次 monitor 偵測到 path 翻轉，arm (PTR+1)%N 到新 bg，PTR = (PTR+1)%N
# - 如此 P × N 次的實際播放序列為 0,1,2,...,N-1,0,1,...
QUEUE_PTR = 0
NEXT_DATA_OFFSET = 0

# 極速操作位元封裝
BYTES_ZERO      = struct.pack("<I", 0)
BYTES_ONE       = struct.pack("<I", 1)
BYTES_DMA_RESET = struct.pack("<I", 0x0004)
BYTES_DMA_RUN    = struct.pack("<I", 0x0011)
BYTES_DMA_TAIL   = struct.pack("<I", 0xFFFFFFF0)

# 硬體暫存器位址定義
CLOCK_BASE     = 0x81240000
TRIG_CTRL_BASE = 0x81250000
PATH_CTRL_BASE = 0x81270000
GPIO_ADDRS     = [0x81200000, 0x81210000, 0x81220000, 0x81230000]

GPIO_CH1_DATA, GPIO_CH1_TRI = 0x00, 0x04
GPIO_CH2_DATA, GPIO_CH2_TRI = 0x08, 0x0C

# =============================================================================
# IP 快取與名單管理 (整合 Identify 'I' 指令)
# =============================================================================
SLAVE_IP_CACHE = {}

def load_slave_registry():
    """啟動時讀取 Bash 腳本產生的 active_slaves.txt"""
    global SLAVE_IP_CACHE
    if not IS_MASTER: return
    
    if os.path.exists(SLAVES_REGISTRY_FILE):
        try:
            with open(SLAVES_REGISTRY_FILE, "r") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) == 2:
                        ip, name = parts
                        SLAVE_IP_CACHE[name.lower()] = ip
            print(f"[*] 已從系統名單載入實體 IP 名單: {SLAVE_IP_CACHE}")
        except Exception as e:
            print(f"[!] 讀取名單失敗: {e}")

def update_slave_ip(hostname, ip):
    """當 Slave 主動報到 (指令 'I') 時，更新快取與檔案"""
    global SLAVE_IP_CACHE
    hostname = hostname.lower()
    SLAVE_IP_CACHE[hostname] = ip
    
    with REGISTRY_LOCK:
        try:
            lines = [f"{ip} {hostname}"]
            if os.path.exists(SLAVES_REGISTRY_FILE):
                with open(SLAVES_REGISTRY_FILE, "r") as f:
                    for line in f:
                        if not line.strip().endswith(f" {hostname}"):
                            lines.append(line.strip())
            with open(SLAVES_REGISTRY_FILE, "w") as f:
                f.write("\n".join(lines) + "\n")
        except Exception as e:
            print(f"[!] 更新註冊表檔案失敗: {e}")

def register_to_master():
    """Slave 啟動時，主動向 Master 的 AWG 服務 (Port 5000) 報到 (指令 'I')"""
    if IS_MASTER: return
    
    print(f"[*] 嘗試向 Master 註冊服務 (Identity)...")
    while RUNNING:
        try:
            master_ip = socket.gethostbyname("eclypse-master.local")
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(2.0)
                s.connect((master_ip, 5000))
                
                name_bytes = MY_HOSTNAME.encode('ascii').ljust(16, b'\x00')
                header = name_bytes + b'I' + struct.pack("<I", 0)
                
                s.sendall(header)
                resp = s.recv(1024).decode('ascii')
                
                if "OK" in resp:
                    print(f"[✔] 服務報到成功！Master IP: {master_ip}")
                    return
        except Exception:
            time.sleep(5)

# =============================================================================
# 狀態監控執行緒 = 駐列推進引擎
# =============================================================================
# 設計理念：
#   雙方的 monitor 各自獨立偵測 path 翻轉事件，看到變化就 arm 下一組到新背景。
#   QUEUE_PTR 語意：「目前已 arm 在背景 path 等待下次 P 播放的索引」
#   - 翻轉發生 → 上次已 arm 在背景的那組 (= 舊 PTR) 變成 active 開始播
#   - arm (舊 PTR + 1) 到新背景，更新 PTR = 舊 PTR + 1
# =============================================================================

def status_monitor_thread():
    """背景監視器 + 駐列推進引擎"""
    global MONITOR_LAST_PATH, QUEUE_PTR
    
    last_clk_source = -1
    last_clk_reset = -1
    
    while RUNNING:
        clk_data_ch1 = struct.unpack("<I", M_CLK_CTRL[0x00:0x04])[0] & 0x1
        clk_data_ch2 = struct.unpack("<I", M_CLK_CTRL[0x08:0x0C])[0] & 0x1
        path_data    = struct.unpack("<I", M_PATH_CTRL[0x08:0x0C])[0] & 0x1
        
        if clk_data_ch1 != last_clk_reset:
            status = "【工作模式】" if clk_data_ch1 == 1 else "【重置模式(RESET)】"
            print(f"\n[偵測] Mux Reset 狀態變更: {status}")
            last_clk_reset = clk_data_ch1

        if clk_data_ch2 != last_clk_source:
            source = "INTERNAL (Master)" if clk_data_ch2 == 1 else "EXTERNAL (Remote)"
            print(f"[偵測] 時鐘來源設定變更為: {source}")
            last_clk_source = clk_data_ch2

        # --- Path 翻轉偵測 → 駐列自動推進 ---
        if path_data != MONITOR_LAST_PATH:
            if MONITOR_LAST_PATH != -1:
                print(f"\n[偵測] 硬體 Path 跳變: {MONITOR_LAST_PATH} ===> {path_data}")
                
                with QUEUE_LOCK:
                    if WAVE_QUEUE:
                        # 翻轉發生的瞬間：
                        #   - 舊背景 path (之前 arm 過 idx=QUEUE_PTR 那組) 變成 active，開始播 idx=QUEUE_PTR
                        #   - 舊 active path 變成新背景，需要 arm 下一組 (PTR+1)
                        # 所以「目前正在播的 idx」就是 QUEUE_PTR (還沒推進前的值)
                        now_playing = QUEUE_PTR
                        next_arm_idx = (QUEUE_PTR + 1) % len(WAVE_QUEUE)
                        new_bg = MONITOR_LAST_PATH   # 剛被切走的舊 active = 新背景
                        
                        with HW_LOCK:
                            arm_wave_to_specific_path(WAVE_QUEUE[next_arm_idx], new_bg)
                        
                        QUEUE_PTR = next_arm_idx
                        print(f"[自動推進] 開始播放 idx {now_playing} (Path {path_data}) | "
                              f"已預載 idx {next_arm_idx} 到 Path {new_bg}")
                    else:
                        # 駐列為空 (例如 S 指令後或 X 重置後) → 跳過自動推進
                        print(f"[!] Path 跳變但駐列為空，跳過自動推進 (Stop 狀態？)")
            else:
                print(f"[*] Monitor 建立 path 基準線: {path_data}")
            
            MONITOR_LAST_PATH = path_data
            
        time.sleep(0.01)

# =============================================================================
# 2. 設定檔與硬體初始化管理
# =============================================================================

def load_calibration_config():
    default_calib = [{"mult": 0x0F207, "add": 0x00260}, {"mult": 0x0F026, "add": 0x3FFD0}, {"mult": 0x0F200, "add": 0x00000}, {"mult": 0x0F200, "add": 0x00000}]
    if os.path.exists(CALIB_FILE):
        try:
            with open(CALIB_FILE, "r") as f:
                print(f"[*] 成功讀取校正檔 {CALIB_FILE}")
                return json.load(f)
        except Exception: return default_calib
    return default_calib

def load_clock_config():
    if os.path.exists(CLOCK_FILE):
        try:
            with open(CLOCK_FILE, "r") as f:
                print(f"[*] 成功讀取時鐘設定檔 {CLOCK_FILE}")
                return json.load(f)
        except Exception: return {"source": 1 if IS_MASTER else 0}
    return {"source": 1 if IS_MASTER else 0}

def apply_calibration_to_hw(fd, ch_idx, mult, add):
    addr = GPIO_ADDRS[ch_idx]
    with mmap.mmap(fd, 0x100, offset=addr) as m_cal:
        m_cal[GPIO_CH1_TRI:GPIO_CH1_TRI+4] = BYTES_ZERO 
        m_cal[GPIO_CH2_TRI:GPIO_CH2_TRI+4] = BYTES_ZERO
        m_cal[GPIO_CH1_DATA:GPIO_CH1_DATA+4] = struct.pack("<I", mult)
        m_cal[GPIO_CH2_DATA:GPIO_CH2_DATA+4] = struct.pack("<I", add)
    print(f"    - CH{ch_idx+1} 校正套用: Mult=0x{mult:05X}, Add=0x{add:05X}")

def init_zero_wave(fd):
    """在 SRAM 末端寫入全零波形，供 S 指令使用"""
    print(f"[*] 初始化全零波形保留區 @ {hex(ZERO_WAVE_PHYS_A)} ({ZERO_WAVE_RESERVED_SIZE//1024} KB)")
    
    # 以全零填滿整個保留區 (兩個 path 都包含)
    # 注意：14-bit signed DAC 中，0x00000000 對應到 0V (中點)
    zero_bytes = b'\x00' * ZERO_WAVE_RESERVED_SIZE
    with mmap.mmap(fd, ZERO_WAVE_RESERVED_SIZE, offset=ZERO_WAVE_PHYS_A) as m:
        m[0:ZERO_WAVE_RESERVED_SIZE] = zero_bytes
    
    print(f"    - Path A 全零位址: {hex(ZERO_WAVE_PHYS_A)}")
    print(f"    - Path B 全零位址: {hex(ZERO_WAVE_PHYS_B)}")
    print(f"    - 每 path 長度: {ZERO_WAVE_LEN} bytes ({ZERO_WAVE_LEN//4} 個 DMA word)")

def init_hardware(fd):
    global M_PATH_CTRL, M_TRIG_CTRL, M_CLK_CTRL, M_DMA, M_DESC
    print(f"[*] 執行系統硬體初始化程序 (V5.6.5 叢集連動版)...")
    
    M_PATH_CTRL = mmap.mmap(fd, 0x100, offset=PATH_CTRL_BASE)
    M_TRIG_CTRL = mmap.mmap(fd, 0x100, offset=TRIG_CTRL_BASE)
    M_CLK_CTRL  = mmap.mmap(fd, 0x100, offset=CLOCK_BASE)

    # DMA 控制區 + 描述符池常駐映射，消滅 mmap 延遲
    for i in range(4):
        M_DMA[i]  = mmap.mmap(fd, 0x100,             offset=DMA_BASES[i])
        M_DESC[i] = mmap.mmap(fd, DESC_REGION_SIZE,  offset=DESC_ADDRS[i])
    print(f"[*] DMA / 描述符池常駐映射建立完成 (4x DMA + 4x DESC)")

    M_PATH_CTRL[GPIO_CH1_TRI:GPIO_CH1_TRI+4] = BYTES_ZERO
    M_PATH_CTRL[GPIO_CH2_TRI:GPIO_CH2_TRI+4] = BYTES_ONE

    M_TRIG_CTRL[0x04:0x08] = BYTES_ZERO
    M_TRIG_CTRL[0x0C:0x10] = BYTES_ZERO
    M_TRIG_CTRL[0x08:0x0C] = BYTES_ONE if IS_MASTER else BYTES_ZERO
    M_TRIG_CTRL[0x00:0x04] = BYTES_ZERO # 初始 Gate 關閉，後續在 __main__ 永遠開啟

    M_CLK_CTRL[GPIO_CH1_TRI:GPIO_CH1_TRI+4] = BYTES_ZERO 
    M_CLK_CTRL[GPIO_CH1_DATA:GPIO_CH1_DATA+4] = BYTES_ZERO 
    time.sleep(0.1) 
    M_CLK_CTRL[GPIO_CH1_DATA:GPIO_CH1_DATA+4] = BYTES_ONE 
    
    clk_cfg = load_clock_config()
    M_CLK_CTRL[GPIO_CH2_TRI:GPIO_CH2_TRI+4] = BYTES_ZERO
    M_CLK_CTRL[GPIO_CH2_DATA:GPIO_CH2_DATA+4] = BYTES_ONE if clk_cfg["source"] == 1 else BYTES_ZERO

    calib_data = load_calibration_config()
    for i in range(4):
        apply_calibration_to_hw(fd, i, calib_data[i]["mult"], calib_data[i]["add"])
    
    # 寫入全零波形
    init_zero_wave(fd)
    
    print(f"[✔] 硬體初始化與全域映射全數完成。\n")

# =============================================================================
# 3. 硬體核心操作與極速切換
# =============================================================================

def get_active_path_fast():
    return struct.unpack("<I", M_PATH_CTRL[0x08:0x0C])[0] & 0x1

def toggle_dma_path_fast():
    """移除 mmap 與 sleep。利用寫入指令間隔產生的脈衝寬度已足夠觸發 FPGA 邏輯"""
    M_PATH_CTRL[0x00:0x04] = BYTES_ZERO
    M_PATH_CTRL[0x00:0x04] = BYTES_ONE
    for _ in range(50): pass 
    M_PATH_CTRL[0x00:0x04] = BYTES_ZERO

def arm_wave_to_specific_path(wave_meta, target_path):
    """將駐列中的波形武裝至特定的硬體路徑 (0 或 1)"""
    p_a, p_b, length = wave_meta
    idx_a, idx_b = target_path, target_path + 2
    
    for (idx, phys_addr) in [(idx_a, p_a), (idx_b, p_b)]:
        m_d = M_DESC[idx]
        m_d[0:32]  = struct.pack("<IIIIIIII", DESC_ADDRS[idx]+64, 0, phys_addr, 0, 0, 0, length|0x0C000000, 0)
        m_d[64:96] = struct.pack("<IIIIIIII", DESC_ADDRS[idx],    0, phys_addr, 0, 0, 0, length|0x0C000000, 0)
        
        m_dma = M_DMA[idx]
        m_dma[0x00:0x04] = BYTES_DMA_RESET
        m_dma[0x08:0x0C] = struct.pack("<I", DESC_ADDRS[idx])      
        m_dma[0x00:0x04] = BYTES_DMA_RUN
        m_dma[0x10:0x14] = BYTES_DMA_TAIL
    print(f"    [✔] 波形預填成功: Path {target_path} 已指向位址 {hex(p_a)}")

def reset_bg_pipeline():
    for idx in range(4):
        M_DMA[idx][0x00:0x04] = BYTES_DMA_RESET

def graceful_shutdown(signum, frame):
    global RUNNING
    RUNNING = False
    print("\n[!] 執行安全硬體停機程序...")
    if M_PATH_CTRL: M_PATH_CTRL.close()
    if M_TRIG_CTRL: M_TRIG_CTRL.close()
    if M_CLK_CTRL: M_CLK_CTRL.close()
    for m in M_DMA:
        if m: m.close()
    for m in M_DESC:
        if m: m.close()
    sys.exit(0)

# =============================================================================
# 4. 網路伺服器、路由轉發與駐列邏輯
# =============================================================================

def recv_exact(sock, length):
    data = bytearray()
    while len(data) < length:
        packet = sock.recv(length - len(data))
        if not packet: return None
        data.extend(packet)
    return data

def forward_to_slave(target_hostname, payload):
    """優先使用 SLAVE_IP_CACHE，消除轉發時的 DNS 解析延遲"""
    target_key = target_hostname.lower()
    target_ip = SLAVE_IP_CACHE.get(target_key)
    if not target_ip:
        try:
            target_ip = socket.gethostbyname(f"{target_hostname}.local")
            SLAVE_IP_CACHE[target_key] = target_ip
        except: target_ip = f"{target_hostname}.local"

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            s.settimeout(3.0)
            s.connect((target_ip, 5000))
            s.sendall(payload)
            return s.recv(1024)
    except Exception as e:
        print(f"[X] 轉發失敗: {e}")
        return b"ERR_FORWARD"

def handle_client(conn, addr):
    global NEXT_DATA_OFFSET, QUEUE_PTR, WAVE_QUEUE, LAST_P_TIME, MONITOR_LAST_PATH
    
    try:
        header = conn.recv(21)
        if not header: return
        target_name = header[0:16].decode('ascii').strip('\x00').lower()
        cmd = chr(header[16])
        n_points = struct.unpack("<I", header[17:21])[0]

        # 1. 路由轉發邏輯
        if target_name != MY_HOSTNAME and IS_MASTER:
            data = recv_exact(conn, n_points * 8) if cmd == 'D' else b""
            forward_to_slave(target_name, header + data)
            conn.sendall(b"OK_FORWARDED")
            return

        # 2. 本地指令執行邏輯
        with HW_LOCK: 
            if cmd == 'D': # --- 加入序列駐列 ---
                raw_data = recv_exact(conn, n_points * 8)
                data_len = len(raw_data)
                half_len = data_len // 2
                
                with QUEUE_LOCK:
                    if len(WAVE_QUEUE) >= MAX_QUEUE_SIZE:
                        conn.sendall(b"ERR_QUEUE_FULL")
                        return
                    # [V5.6.3] 邊界檢查改用 USABLE_DATA_POOL_SIZE (扣掉零波形保留區)
                    if (NEXT_DATA_OFFSET + data_len) > USABLE_DATA_POOL_SIZE:
                        conn.sendall(b"ERR_SRAM_FULL")
                        return
                    
                    phys_a = DATA_POOL_BASE + NEXT_DATA_OFFSET
                    phys_b = phys_a + half_len
                    
                    matrix = np.frombuffer(raw_data, dtype=np.int16).reshape(-1, 4)
                    w_a = (((matrix[:,0].astype(np.uint32)&0x3FFF)<<18) | ((matrix[:,1].astype(np.uint32)&0x3FFF)<<2)).tobytes()
                    w_b = (((matrix[:,2].astype(np.uint32)&0x3FFF)<<18) | ((matrix[:,3].astype(np.uint32)&0x3FFF)<<2)).tobytes()
                    
                    with mmap.mmap(FD, data_len, offset=phys_a) as m:
                        m[0:half_len] = w_a
                        m[half_len:data_len] = w_b
                    
                    WAVE_QUEUE.append((phys_a, phys_b, half_len))
                    
                    # 推進 NEXT_DATA_OFFSET 並 round up 至 4KB 邊界，確保對齊
                    NEXT_DATA_OFFSET = (NEXT_DATA_OFFSET + data_len + PAGE_MASK) & ~PAGE_MASK
                    
                    # [安全初始化預填] 第一組自動載入到背景
                    if len(WAVE_QUEUE) == 1:
                        curr_active = get_active_path_fast()
                        bg_path = 1 - curr_active
                        arm_wave_to_specific_path(WAVE_QUEUE[0], bg_path)
                        QUEUE_PTR = 0   # 背景上現在 arm 著 idx 0
                        MONITOR_LAST_PATH = curr_active
                        print(f"[*] 載入首組波形並自動預填至 Path {bg_path} (PTR=0)")
                        print(f"[*] Monitor 基準線同步為 Path {curr_active}")
                
                print(f"[*] 駐列進度: {len(WAVE_QUEUE)}/16 | 已用空間: {NEXT_DATA_OFFSET/1024/1024:.1f}MB")
                conn.sendall(f"OK_QUEUED_{len(WAVE_QUEUE)-1}".encode())

            elif cmd == 'P': # --- 純 toggle，駐列推進交給 monitor ---
                with QUEUE_LOCK:
                    if not WAVE_QUEUE:
                        conn.sendall(b"ERR_EMPTY_QUEUE")
                        return
                
                now = time.monotonic()
                elapsed = now - LAST_P_TIME
                if elapsed < P_COOLDOWN_SEC:
                    wait = P_COOLDOWN_SEC - elapsed
                    print(f"[*] P 指令冷卻中，補 sleep {wait*1000:.1f}ms")
                    time.sleep(wait)
                
                if IS_MASTER:
                    toggle_dma_path_fast()
                
                LAST_P_TIME = time.monotonic()
                conn.sendall(b"OK_P_TRIGGERED")

            elif cmd == 'X': # --- 徹底重置駐列與 SRAM 指標 ---
                with QUEUE_LOCK:
                    WAVE_QUEUE.clear()
                    QUEUE_PTR = 0
                    NEXT_DATA_OFFSET = 0
                    MONITOR_LAST_PATH = -1
                    print("[!] 駐列已清空，SRAM 池偏移量與 Monitor 基準線已重置。")
                reset_bg_pipeline()
                conn.sendall(b"OK_QUEUE_RESET")

            elif cmd == 'S': # --- [V5.6.5 修復] 叢集連動停止 ---
                print("[!] 收到停止指令：準備安全停機並全叢集歸零...")
                
                # 1. Master 負責廣播 'S' 指令給所有已知的 Slave
                if IS_MASTER:
                    print("[*] 正在廣播停止指令 (S) 至所有已連線的 Slave...")
                    for slave_name in list(SLAVE_IP_CACHE.keys()):
                        s_header = slave_name.encode('ascii').ljust(16, b'\x00') + b'S' + struct.pack("<I", 0)
                        # forward_to_slave 是阻塞式的，會確保 Slave 成功收到並武裝 ZERO_WAVE
                        resp = forward_to_slave(slave_name, s_header)
                        print(f"    - Slave [{slave_name}] 歸零準備: {resp.decode('ascii', errors='ignore')}")

                # 2. 本機 (Master/Slave 皆同) 清空駐列並武裝全零波形
                with QUEUE_LOCK:
                    WAVE_QUEUE.clear()
                    QUEUE_PTR = 0
                    NEXT_DATA_OFFSET = 0
                    
                    # 兩個 path 都 arm 全零波形，確保不管 active 在哪邊都輸出 0V
                    arm_wave_to_specific_path(ZERO_WAVE_META, 0)
                    arm_wave_to_specific_path(ZERO_WAVE_META, 1)
                    
                    # 3. 只有 Master 需要發射最終同步脈衝
                    if IS_MASTER:
                        now = time.monotonic()
                        elapsed = now - LAST_P_TIME
                        if elapsed < P_COOLDOWN_SEC:
                            time.sleep(P_COOLDOWN_SEC - elapsed)
                        print("[*] 發送最終硬體同步脈衝，全叢集 DAC 歸零。")
                        toggle_dma_path_fast()
                        LAST_P_TIME = time.monotonic()
                        # 注意：此處已移除關閉閘門 (M_TRIG_CTRL = BYTES_ZERO) 的邏輯
                        # 讓閘門常開以確保持續輸出 0V
                
                conn.sendall(b"OK_STOPPED_ZERO")
            
            elif cmd == 'I': # --- Identity 報到指令 ---
                update_slave_ip(target_name, addr[0])
                conn.sendall(b"OK_IDENTITY_ACCEPTED")
            
            elif cmd == 'R': # --- 本地重置背景管道 ---
                reset_bg_pipeline()
                conn.sendall(b"OK_LOCAL_RESET")

            elif cmd == 'C': # --- 時鐘來源設定 ---
                mode = n_points 
                M_CLK_CTRL[GPIO_CH2_DATA:GPIO_CH2_DATA+4] = BYTES_ONE if mode == 1 else BYTES_ZERO
                conn.sendall(b"OK_CLOCK_SET")

            elif cmd == 'K': # --- 校正參數更新 ---
                cal_idx = n_points 
                cal_data = conn.recv(8)
                mult, add = struct.unpack("<II", cal_data)
                apply_calibration_to_hw(FD, cal_idx, mult, add)
                conn.sendall(b"OK_CALIB_UPDATED")

    except Exception as e:
        print(f"[!] 指令執行解析異常: {e}")
    finally:
        conn.close()

# =============================================================================
# 5. 主程式入口與伺服器啟動
# =============================================================================
if __name__ == "__main__":
    signal.signal(signal.SIGINT, graceful_shutdown)
    signal.signal(signal.SIGTERM, graceful_shutdown)
    
    print(f"\n[BOOT] {MY_HOSTNAME} 正在啟動序列預取服務 (V5.6.5)...")
    FD = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    
    init_hardware(FD)

    threading.Thread(target=status_monitor_thread, daemon=True).start()
    print(f"[*] 狀態監視器 + 駐列推進引擎已啟動。")
    
    if IS_MASTER:
        load_slave_registry()
    else:
        threading.Thread(target=register_to_master, daemon=True).start()

    # [V5.6.3] 開機時就把兩個 path 都 arm 全零，避免 DAC 卡在開機隨機值
    print(f"[*] 開機預熱：將兩個 path 都 arm 全零波形")
    arm_wave_to_specific_path(ZERO_WAVE_META, 0)
    arm_wave_to_specific_path(ZERO_WAVE_META, 1)
    
    if IS_MASTER:
        # [V5.6.4] 開啟執行閘門並永遠保持開啟，確保 DMA 餵入的數據 (包含 0V) 能夠輸出
        M_TRIG_CTRL[GPIO_CH1_DATA:GPIO_CH1_DATA+4] = BYTES_ONE

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', 5000))
    server.listen(10)
    
    print(f"=======================================================")
    print(f"    AWG 序列駐列伺服器就緒 | Node: {MY_HOSTNAME}")
    print(f"    SRAM 分割: {USABLE_DATA_POOL_SIZE//1024//1024}MB Data / "
          f"{ZERO_WAVE_RESERVED_SIZE//1024}KB Zero / 1MB Desc")
    print(f"    版本: V5.6.5 (Cluster Sync Stop - Fully Commented)")
    print(f"    P 指令冷卻: {P_COOLDOWN_SEC*1000:.0f}ms")
    print(f"=======================================================\n")
    
    while RUNNING:
        try:
            conn, addr = server.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()
        except Exception:
            break