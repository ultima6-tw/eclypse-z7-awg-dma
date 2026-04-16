from awg_client import update_remote_calibration

# 假設你量測發現 slave3 的 CH2 (index=1) 需要微調 multiplier
target = "eclypse-slave3"
channel = 1
new_mult = 0x0F250  # 你計算出的新校正值
new_add = 0x3FFD0   # 維持原本的 offset

update_remote_calibration(target, channel, new_mult, new_add)
print(f"[✔] {target} CH{channel+1} 校正完畢！")