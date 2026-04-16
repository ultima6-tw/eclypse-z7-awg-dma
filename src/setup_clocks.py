from awg_client import set_remote_clock

# 設定 Master 為內部時鐘
set_remote_clock("eclypse-master", 1)

# 利用迴圈一次設定所有的 Slave 為外部時鐘
for i in range(1, 101):  # 假設你有 slave1 ~ slave100
    target = f"eclypse-slave{i}"
    print(f"[*] 設定 {target} 時鐘...")
    set_remote_clock(target, 0)