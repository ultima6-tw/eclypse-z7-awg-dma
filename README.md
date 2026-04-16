# Eclypse Z7 AWG + DMA

A distributed arbitrary waveform generator (AWG) system for the [Digilent Eclypse Z7](https://digilent.com/reference/programmable-logic/eclypse-z7/start) board, using AXI DMA to stream pre-computed waveform samples directly to dual Zmod DACs.

## System Overview

Waveform samples are computed on the host PC (via NumPy) and sent over TCP to a daemon running on PetaLinux. The daemon writes samples into SRAM via `/dev/mem`, then drives 4 AXI DMA engines to push data to the DACs. The FPGA handles routing, clock distribution, and multi-board hardware synchronization.

```
[Host PC]
  play_waves.py ──TCP:5000──► awg_daemon.py (PetaLinux)
                                     │ /dev/mem mmap
                               ┌─────┴─────┐
                            DMA 0/1      DMA 2/3
                           (Pod A)      (Pod B)
                               └─────┬─────┘
                              dac_master_controller
                               ┌─────┴─────┐
                          ZmodAWG_0    ZmodAWG_1
                           Pod A        Pod B
                          (CH1+CH2)   (CH3+CH4)
```

Each board outputs **4 channels** (2 per Zmod DAC pod, 14-bit @ up to 100 MSPS).

---

## Multi-Board Synchronization

Multiple boards can be synchronized via PMOD connectors. One board acts as **Master** (generates clock and triggers), the rest are **Slaves** (follow).

```
Master Board                    Slave Board(s)
─────────────────────           ─────────────────────
clk_10M_out[1:0]  ──────────►  ext_clock_in  (G15)
dma_trigger_out[1:0] ───────►  dma_trigger_in (D16)
dac_trigger_out[1:0] ───────►  dac_trigger_in (D17)
```

Role is determined automatically at boot by `auto_setup.sh` — if `eclypse-master.local` is not found on the network, the board becomes Master.

---

## Repository Structure

```
├── vivado/
│   ├── 20250910_z7_awg.xpr          # Vivado project file (2025.1)
│   ├── design_1_wrapper.xsa         # Exported hardware platform
│   ├── set_cdc_iso.tcl              # CDC clock group constraints
│   └── 20250910_z7_awg.srcs/
│       ├── constrs_1/new/
│       │   ├── pins.xdc             # Pin assignments & I/O standards
│       │   └── timing_late_v2.xdc  # Timing exceptions & false paths
│       ├── sim_1/.../tb_top.v       # Testbench
│       └── sources_1/
│           ├── bd/design_1/design_1.bd    # Block design
│           └── new/
│               ├── dac_master_controller.v  # AXI-Stream path switcher
│               └── my_clk_mux.v             # Clock mux & forwarding
└── src/
    ├── auto_setup.sh     # One-time board initialization (network + services)
    ├── awg_daemon.py     # Hardware control daemon (runs on board)
    ├── awg_client.py     # TCP client library (runs on host PC)
    ├── play_waves.py     # Example: generate and play waveforms
    ├── setup_clocks.py   # Set clock source (master/slave) across cluster
    └── calibrate_dac.py  # Update DAC gain/offset calibration
```

---

## FPGA Design

### Active Modules

| Module | Role |
|--------|------|
| `design_1.bd` | Block design: PS, 4× AXI DMA, 4× AXIS FIFO, 2× ZmodAWGController, GPIOs, clocks |
| `dac_master_controller.v` | Routes 4 DMA streams to 2 DAC pods; dual-buffer path switching |
| `my_clk_mux.v` | Selects internal/external 10 MHz reference; forwards clock to Slave boards via ODDR |

### Data Path

```
ARM DDR3
  └─► axi_dma_b1_1 / b1_2   (Pod A streams)
  └─► axi_dma_b2_1 / b2_2   (Pod B streams)
        │
        ▼
  axis_data_fifo (×4)
        │
        ▼
  dac_master_controller
    ├─ path_reg=0: s0→Pod A,  s2→Pod B
    └─ path_reg=1: s1→Pod A,  s3→Pod B
        │
        ▼
  ZmodAWGController_0 → DAC Pod A (14-bit)
  ZmodAWGController_1 → DAC Pod B (14-bit)
```

### Dual-Buffer Path Switching

The `dac_master_controller` supports seamless waveform switching:
- `dma_path` (pulse): each rising edge toggles `path_reg`, switching between stream pairs (s0/s2 ↔ s1/s3)
- `dac_run` (level): gates TVALID — set to 1 to start output, 0 to silence

This allows the ARM to load the next waveform into the background path while the foreground path is actively playing, then switch instantly with a single pulse.

### Clock Domains

| Domain | Frequency | Source |
|--------|-----------|--------|
| PS (ARM) | 125 MHz | processing_system7 |
| DAC clock | 125 MHz | clk_wiz_1 |
| Reference (PL) | 10 MHz | clk_wiz_2 or external PMOD |

`my_clk_mux` uses a `BUFGMUX` to switch between internal and external 10 MHz. On mode change, a 65536-cycle reset pulse is issued to allow the downstream MMCM to re-lock.

---

## Software (PetaLinux Daemon)

### Setup

1. Copy `awg_daemon.py` to `/home/petalinux/` on each board
2. Run `auto_setup.sh` as root — this configures networking (mDNS), assigns hostnames (`eclypse-master`, `eclypse-slave1`, ...), and registers `awg_daemon.py` as a systemd service

```bash
sudo bash auto_setup.sh
```

The board will reboot and the daemon starts automatically on boot.

### Memory Layout (SRAM, 256 MB @ 0x30000000)

```
0x30000000 ~ 0x3FEEFFFF  : Waveform data pool (~254.9 MB)
0x3FEF0000 ~ 0x3FEFFFFF  : Reserved: zero-waveform (64 KB)
0x3FF00000 ~ 0x3FFFFFFF  : DMA descriptor pool (1 MB, 4 × 64 KB)
```

### Waveform Data Format

Each sample point contains 4 × int16 values (CH1, CH2, CH3, CH4). The daemon packs them into 32-bit DMA words:

```python
w_a = ((ch1 & 0x3FFF) << 18) | ((ch2 & 0x3FFF) << 2)  # Pod A
w_b = ((ch3 & 0x3FFF) << 18) | ((ch4 & 0x3FFF) << 2)  # Pod B
```

### TCP Command Protocol

All commands are sent to port **5000** on the Master board. The Master automatically forwards commands addressed to a Slave.

**Packet header (21 bytes):**
```
[0:16]  target hostname (ASCII, zero-padded)
[16]    command byte
[17:21] n_points (uint32 LE)
```

| Command | Payload | Description |
|---------|---------|-------------|
| `D` | `n_points × 8 bytes` of int16×4 | Queue a waveform segment into SRAM |
| `P` | — | Trigger path switch (play next queued waveform) |
| `S` | — | Stop all boards, output 0 V |
| `X` | — | Reset queue and SRAM pointer |
| `C` | n_points = 1 (internal) / 0 (external) | Set clock source |
| `K` | n_points = ch_idx; 8 bytes (mult, add) | Update DAC calibration |
| `I` | — | Slave identity registration |

### Queue & Playback

The daemon maintains a waveform queue (up to 16 segments). A background monitor thread watches `current_path` register and automatically arms the next segment into the idle path each time a switch is detected:

```
D → arm segment[0] to background path
P → hardware toggle → segment[0] becomes active
    monitor detects flip → arm segment[1] to new background
P → hardware toggle → segment[1] becomes active
    ...
```

---

## Host PC Usage

### Dependencies

```bash
pip install numpy
```

### Quickstart

```python
from awg_client import send_awg_command
import numpy as np

fs = 100e6
n = 1000
t = np.arange(n) / fs
freq = 1e6
amp = 8191

ch1 = np.int16(np.round(np.sin(2 * np.pi * freq * t) * amp))
ch2 = np.int16(np.round(np.sin(2 * np.pi * freq * t + np.pi/2) * amp))
ch3 = np.int16(np.zeros(n))
ch4 = np.int16(np.zeros(n))
data = np.column_stack((ch1, ch2, ch3, ch4)).tobytes()

send_awg_command("eclypse-master", cmd='X')           # reset
send_awg_command("eclypse-master", cmd='D', n_points=n, data=data)  # load
send_awg_command("eclypse-master", cmd='P')           # play
```

See `play_waves.py` for a full multi-board example with phase compensation.

### Clock Setup

```bash
python3 setup_clocks.py
```

Sets Master to use internal clock and all Slaves to use external (from Master PMOD).

### DAC Calibration

Calibration coefficients (gain multiplier and offset) are stored in `dac_calib.json` on each board. To update remotely:

```bash
python3 calibrate_dac.py
```

---

## Hardware Requirements

- [Digilent Eclypse Z7](https://digilent.com/reference/programmable-logic/eclypse-z7/start)
- [Zmod DAC 1411](https://digilent.com/reference/zmod/zmododac/start) × 2 (one per board, or two per board for 4-channel output)
- Vivado 2025.1 (to rebuild bitstream)
- PetaLinux image with Python 3 and NumPy
