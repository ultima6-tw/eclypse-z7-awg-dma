import numpy as np
import time
import sys
import signal
# 從你自己的 library 匯入網路控制函數
from awg_client import send_awg_command

MASTER_NODE = "eclypse-master"
SLAVE_NODE = "eclypse-slave1" 

# =============================================================================
# [新增] 終極安全停機處理器 (攔截各種關閉方式)
# =============================================================================
def emergency_stop(signum, frame):
    print(f"\n[!] 偵測到程式即將關閉 (訊號: {signum})，正在執行全叢集安全停機...")
    try:
        # 嘗試發送 S 指令給 Master，Master 會負責廣播給所有 Slave
        send_awg_command(MASTER_NODE, cmd='S')
        print("[✔] 停機指令發送成功。")
    except Exception as e:
        print(f"[X] 停機指令發送失敗: {e}")
    sys.exit(0)

# 註冊訊號攔截
signal.signal(signal.SIGINT, emergency_stop)   # 攔截 Ctrl+C
signal.signal(signal.SIGTERM, emergency_stop)  # 攔截 kill 指令
if hasattr(signal, 'SIGHUP'):
    signal.signal(signal.SIGHUP, emergency_stop)   # 攔截終端機視窗被直接關閉 (Linux/WSL/Mac)

# =============================================================================
# 0. 系統初始化 (重置駐列與記憶體池)
# =============================================================================
print("=== 0. 清空叢集駐列與記憶體池 ===")
send_awg_command(SLAVE_NODE, cmd='X')
time.sleep(0.1)
send_awg_command(MASTER_NODE, cmd='X')
time.sleep(0.1)

# =============================================================================
# 1. 產生並部署多組波形資料
# =============================================================================
print("\n=== 1. 產生並部署序列波形資料 (含跨板 17 度相位補償) ===")

fs_awg = 100e6
n_points = 1000
amp = 8191
t = np.arange(n_points) / fs_awg

COMPENSATION_DEG = 17.0
comp_rad = np.radians(COMPENSATION_DEG)
test_freqs = [1e6, 2e6, 3e6]

for idx, freq in enumerate(test_freqs):
    print(f"\n[*] 正在準備第 {idx+1} 組波形 (頻率: {freq/1e6} MHz)...")
    
    m_ch1 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 0) * amp))                 
    m_ch2 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi/2) * amp))            
    m_ch3 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi) * amp))              
    m_ch4 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 3 * np.pi / 2) * amp))      
    master_data = np.column_stack((m_ch1, m_ch2, m_ch3, m_ch4)).tobytes()

    s_ch1 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 0 + comp_rad) * amp))                 
    s_ch2 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi/2 + comp_rad) * amp))            
    s_ch3 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi + comp_rad) * amp))              
    s_ch4 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 3 * np.pi / 2 + comp_rad) * amp))      
    slave_data = np.column_stack((s_ch1, s_ch2, s_ch3, s_ch4)).tobytes()

    send_awg_command(SLAVE_NODE, cmd='D', n_points=n_points, data=slave_data)
    time.sleep(0.05)
    send_awg_command(MASTER_NODE, cmd='D', n_points=n_points, data=master_data)
    time.sleep(0.05)

print("\n[✔] 叢集資料部署完畢！")

# =============================================================================
# 2. 互動式觸發測試 (移除 try...except，因為 signal 已經接管了)
# =============================================================================
print("\n=== 2. 開始循環觸發測試 ===")
print("提示：第一次按下 Enter 時，將會輸出 1MHz 波形。")
print("      按下 Ctrl+C 或直接關閉視窗即可安全結束測試。")

trigger_count = 0
while True:
    # input() 會阻塞在這裡，但如果收到系統訊號，signal handler 會強制打斷它
    input(f"\n[待命] 按 [Enter] 發射第 {trigger_count + 1} 次 P 指令...")
    
    send_awg_command(MASTER_NODE, cmd='P')
    
    trigger_count += 1
    current_freq = test_freqs[(trigger_count - 1) % len(test_freqs)]
    next_freq = test_freqs[trigger_count % len(test_freqs)]
    
    print(f"[🚀] 觸發完成！目前應輸出 {current_freq/1e6} MHz，並已預取 {next_freq/1e6} MHz 待命。")