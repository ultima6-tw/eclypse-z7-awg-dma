import numpy as np
import time
import sys
import signal
from awg_client import send_awg_command

MASTER_NODE = "eclypse-master"
SLAVE_NODE = "eclypse-slave1" 

def emergency_stop(signum, frame):
    print(f"\n[!] 偵測到程式即將關閉 (訊號: {signum})，正在執行全叢集安全停機...")
    try:
        send_awg_command(MASTER_NODE, cmd='S')
        print("[✔] 停機指令發送成功。")
    except Exception as e:
        print(f"[X] 停機指令發送失敗: {e}")
    sys.exit(0)

signal.signal(signal.SIGINT, emergency_stop)
signal.signal(signal.SIGTERM, emergency_stop)
if hasattr(signal, 'SIGHUP'):
    signal.signal(signal.SIGHUP, emergency_stop)

# =============================================================================
# 0. 系統初始化
# =============================================================================
print("=== 0. 清空叢集駐列與記憶體池 ===")
send_awg_command(SLAVE_NODE, cmd='X')
time.sleep(0.1)
send_awg_command(MASTER_NODE, cmd='X')
time.sleep(0.1)

# =============================================================================
# 1. 產生並部署多組波形資料
# =============================================================================
print("\n=== 1. 產生並部署序列波形資料 ===")

fs_awg = 100e6
amp = 8191
n_cycles = 10  # 固定幾個完整週期

COMPENSATION_DEG = 0.0
comp_rad = np.radians(COMPENSATION_DEG)
test_freqs = [1e6, 2e6, 2.5e6]

for idx, freq in enumerate(test_freqs):
    # 計算每個頻率的正確點數
    points_per_cycle = fs_awg / freq
    
    # 檢查是否可以整除
    if not points_per_cycle.is_integer():
        print(f"[!] 警告: {freq/1e6}MHz 無法被 {fs_awg/1e6}MHz 整除！")
        print(f"    每週期點數 = {points_per_cycle:.4f}，可能有相位誤差！")
    
    points_per_cycle = int(points_per_cycle)
    n_points = points_per_cycle * n_cycles
    t = np.arange(n_points) / fs_awg
    
    print(f"\n[*] 第 {idx+1} 組波形: {freq/1e6}MHz, {points_per_cycle}點/週期, 總點數={n_points}")

    m_ch1 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 0) * amp))
    m_ch2 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi/2) * amp))
    m_ch3 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi) * amp))
    m_ch4 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 3*np.pi/2) * amp))
    master_data = np.column_stack((m_ch1, m_ch2, m_ch3, m_ch4)).tobytes()

    s_ch1 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 0 + comp_rad) * amp))
    s_ch2 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi/2 + comp_rad) * amp))
    s_ch3 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi + comp_rad) * amp))
    s_ch4 = np.int16(np.round(np.sin(2 * np.pi * freq * t + 3*np.pi/2 + comp_rad) * amp))
    slave_data = np.column_stack((s_ch1, s_ch2, s_ch3, s_ch4)).tobytes()

    send_awg_command(SLAVE_NODE, cmd='D', n_points=n_points, data=slave_data)
    time.sleep(0.05)
    send_awg_command(MASTER_NODE, cmd='D', n_points=n_points, data=master_data)
    time.sleep(0.05)

print("\n[✔] 叢集資料部署完畢！")

# =============================================================================
# 2. 互動式觸發測試
# =============================================================================
print("\n=== 2. 開始循環觸發測試 ===")
print("提示：第一次按下 Enter 時，將會輸出 1MHz 波形。")
print("      按下 Ctrl+C 或直接關閉視窗即可安全結束測試。")

trigger_count = 0
while True:
    input(f"\n[待命] 按 [Enter] 發射第 {trigger_count + 1} 次 P 指令...")
    
    send_awg_command(MASTER_NODE, cmd='P')
    
    trigger_count += 1
    current_freq = test_freqs[(trigger_count - 1) % len(test_freqs)]
    next_freq = test_freqs[trigger_count % len(test_freqs)]
    
    print(f"[🚀] 觸發完成！目前應輸出 {current_freq/1e6} MHz，並已預取 {next_freq/1e6} MHz 待命。")