#!/usr/bin/env python3
"""
《萝卜突围 / TURNIP TROUBLE》音效合成器
纯代码合成 11 个短音效 -> Ogg Vorbis (44100, mono, 峰值<=0.85)
"""
import os
import sys
import numpy as np
import soundfile as sf

SR = 44100
PEAK = 0.85
# ⚠️ 本脚本就在 art/sfx/ 下，输出目录必须就是脚本所在目录。
# 旧写法拼成 art/sfx/../art/sfx = art/art/sfx（错误目录），会导致重生成写不到真实音效上。
OUT = os.path.dirname(os.path.abspath(__file__))

# 中式五声音阶频率表 (宫商角徵羽: C D E G A)，含跨八度
PENTA = {
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00,
    "C6": 1046.50, "D6": 1174.66, "E6": 1318.51, "G6": 1567.98,
}

def norm(x, peak=PEAK):
    """限幅归一化，给 Ogg Vorbis 解码过冲留 ~10% 余量，绝不削波"""
    mx = np.max(np.abs(x)) + 1e-9
    target = peak * 0.90
    if mx > target:
        x = x * (target / mx)
    return x.astype(np.float32)

def add_silence(x, tail=0.0):
    if tail > 0:
        x = np.concatenate([x, np.zeros(int(SR * tail))])
    return x

def align(x, length):
    """把信号裁剪或补零到指定长度"""
    if len(x) >= length:
        return x[:length]
    return np.concatenate([x, np.zeros(length - len(x))])

def note(freq, dur, wave="sine", amp=1.0, attack=0.005, decay=None, release=0.02):
    """带包络的单音"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    if wave == "sine":
        s = np.sin(2 * np.pi * freq * t)
    elif wave == "triangle":
        s = 2 * np.abs(2 * (freq * t - np.floor(freq * t + 0.5))) - 1
    elif wave == "square":
        s = np.sign(np.sin(2 * np.pi * freq * t))
    elif wave == "saw":
        s = 2 * (freq * t - np.floor(freq * t + 0.5))
    else:
        raise ValueError(wave)
    s = s * amp
    # 指数衰减包络
    dec = decay if decay is not None else dur * 0.7
    env = np.ones(n)
    a_n = int(SR * attack)
    if a_n > 0:
        env[:a_n] = np.linspace(0, 1, a_n)
    rel_n = int(SR * release)
    env = env * np.exp(-np.arange(n) / (SR * dec))
    if rel_n > 0:
        env[-rel_n:] *= np.linspace(1, 0, rel_n)
    return s * env

def noise(dur, amp=1.0, color="white"):
    n = int(SR * dur)
    x = np.random.randn(n) * amp
    if color == "lowpass":
        # 简单一阶低通
        a = 0.85
        y = np.zeros(n)
        prev = 0.0
        for i in range(n):
            prev = a * prev + (1 - a) * x[i]
            y[i] = prev
        x = y
    return x

def bp_sweep_noise(dur, f0, f1, amp=1.0, q=1.2):
    """带通扫频噪声 (whoosh)"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    x = np.random.randn(n) * amp
    # 时变频带通：用复数解调思路近似 -> 逐样本二阶 BPF 较贵，改用乘法+低通
    env = np.linspace(0.2, 1.0, n) * np.exp(-3 * t / dur)[::-1]  # 先弱后强再弱
    # 调制载波：频率随时间从 f0->f1
    phase = 2 * np.pi * np.cumsum(np.linspace(f0, f1, n)) / SR
    carrier = np.sin(phase)
    y = x * carrier
    # 低通平滑保留包络
    a = 0.9
    out = np.zeros(n)
    prev = 0.0
    for i in range(n):
        prev = a * prev + (1 - a) * y[i]
        out[i] = prev
    return out * env * 4.0

def metallic(freqs_amps, dur, amp=1.0, attack=0.002, decay=0.12):
    """金属噪 / 钟磬：多个非谐分音叠加，快衰"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f, a in freqs_amps:
        s += a * np.sin(2 * np.pi * f * t)
    s = s / (np.sum([a for _, a in freqs_amps]) + 1e-9) * amp
    env = np.ones(n)
    a_n = int(SR * attack)
    env[:a_n] = np.linspace(0, 1, a_n)
    env *= np.exp(-np.arange(n) / (SR * decay))
    return s * env

# ---------- 11 个音效 ----------

def sfx_shoot():
    # 清脆短"噗/嗒"：高频三角快速下滑 + 微小噪声点击
    n = int(SR * 0.16)
    t = np.arange(n) / SR
    f = np.linspace(720, 320, n)            # 下滑
    # 柔和化（2026-10-04）：二次泛音 0.25->0.18，起音咔哒 0.25->0.14，
    # 开火是最高频的音效，尖刺感主要来自这两处。
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.8
    s += 0.18 * np.sin(2 * np.pi * 2 * np.cumsum(f) / SR)
    env = np.exp(-t / 0.04)
    env[:int(SR*0.003)] = np.linspace(0, 1, int(SR*0.003))
    s = s * env
    click = noise(0.012, 0.14)
    return norm(add_silence(s[:int(SR*0.16)] + np.concatenate([click, np.zeros(max(0, int(SR*0.16)-len(click)))])[:int(SR*0.16)], 0.005))

def sfx_hit():
    # 闷脆"啪"：低撞击 thud + 短促带通噪声
    # 柔和化（2026-10-04）：亮噪扫频 1800->1100Hz、幅度 0.6->0.32，
    # 命中音每秒可能响十几次，高频成分压下去后整体不再"炸耳"。
    thud = note(150, 0.10, "sine", amp=0.9, attack=0.001, decay=0.05, release=0.02)
    nz = bp_sweep_noise(0.06, 1100, 500, amp=0.32, q=1.0)[:int(SR*0.06)]
    x = thud + np.concatenate([nz, np.zeros(int(SR*0.10)-len(nz))])
    return norm(add_silence(x[:int(SR*0.13)], 0.004))

def sfx_kill():
    # "啵"爆裂上扬：低频快速上滑 + 噪声爆点
    n = int(SR * 0.28)
    t = np.arange(n) / SR
    f = np.linspace(180, 520, n)
    pop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
    pop[:int(SR*0.004)] = np.linspace(0, 1, int(SR*0.004)) * pop[:int(SR*0.004)]
    burst = bp_sweep_noise(0.05, 500, 2500, amp=0.5)[:int(SR*0.05)]
    burst = burst * np.exp(-np.arange(len(burst)) / (SR*0.02))
    x = pop + np.concatenate([burst, np.zeros(n-len(burst))])
    return norm(add_silence(x, 0.004))

def sfx_coin():
    # 柔和版铜钱"叮"（2026-10-04 按玩家反馈重做）
    # 旧版 base=E6(1318Hz) 且叠 2.76x(3639Hz)/5.4x(7120Hz) 非谐分音 —— 高频尖啸，
    # 加上捡钱触发极密，听感是烦躁的"叮叮叮"。改法四步：
    #   1) 降调：E6 -> A5(880Hz)，音高柔和一大截
    #   2) 去非谐：只留 2x/3x 整数倍泛音，删掉 2.76x/5.4x 尖啸分音
    #   3) 慢起音 attack 0.001 -> 0.012，去掉起音"咔哒"
    #   4) 轻度低通 + 整体压到 0.42 音量（捡钱太频繁，响度必须让位）
    base = PENTA["A5"]  # 880.00
    x = metallic([(base, 1.0), (base * 2.0, 0.30), (base * 3.0, 0.10)],
                 dur=0.17, amp=0.85, attack=0.012, decay=0.10)
    L = int(SR * 0.17)
    x = align(x, L)
    x += align(note(base, 0.17, "sine", amp=0.35, attack=0.012, decay=0.09), L)
    x += align(note(base * 1.5, 0.13, "sine", amp=0.10, attack=0.015, decay=0.06), L)
    # 轻度一阶低通（截止约 2.5kHz）：保留基音与 2 倍泛音，磨掉高频毛刺
    a = 0.7
    y = np.zeros(len(x))
    prev = 0.0
    for i in range(len(x)):
        prev = a * prev + (1 - a) * x[i]
        y[i] = prev
    x = norm(y) * 0.42
    return add_silence(x, 0.006)

def sfx_dash():
    # whoosh 风声上滑
    x = bp_sweep_noise(0.30, 350, 2600, amp=0.9, q=1.0)
    return norm(add_silence(x, 0.005))

def sfx_levelup():
    # 上行"叮咚"：G4 B4 D5 (五声徵调)
    seq = [("G4", 0.10), ("D5", 0.10), ("G5", 0.16)]
    out = np.zeros(int(SR * 0.46))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "triangle", amp=0.8, attack=0.004, decay=0.12), seg)
        s += align(note(PENTA[name]*2, d*0.7, "sine", amp=0.2, attack=0.004, decay=0.08), seg)
        out[off:off+seg] += s
        off += int(SR * 0.13)
    return norm(add_silence(out, 0.01))

def sfx_unlock():
    # 更有成就感的"叮铃"双音（上行 + 微光高泛音）
    seq = [("E5", 0.14), ("A5", 0.22)]
    out = np.zeros(int(SR * 0.58))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(metallic([(PENTA[name], 1.0), (PENTA[name]*2.0, 0.6), (PENTA[name]*3.01, 0.25)],
                           dur=d, amp=0.85, attack=0.001, decay=0.14), seg)
        s += align(note(PENTA[name], d, "triangle", amp=0.35, attack=0.003, decay=0.12), seg)
        out[off:off+seg] += s
        off += int(SR * 0.16)
    return norm(add_silence(out, 0.02))

def sfx_victory():
    # 短小号上行琶音：C5 E5 G5 C6 (大三和弦色彩，五声友好)，方波+低通像小号
    seq = [("C5", 0.16), ("E5", 0.16), ("G5", 0.16), ("C6", 0.30)]
    out = np.zeros(int(SR * 1.10))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "saw", amp=0.55, attack=0.01, decay=0.18, release=0.05), seg)
        s += align(note(PENTA[name], d, "square", amp=0.25, attack=0.01, decay=0.18), seg)
        # 轻微低通
        a = 0.82
        y = np.zeros(len(s)); prev = 0.0
        for i in range(len(s)):
            prev = a*prev + (1-a)*s[i]; y[i] = prev
        s = y
        s += align(note(PENTA[name]*2, d*0.6, "sine", amp=0.12, attack=0.01, decay=0.12), seg)
        out[off:off+seg] += s
        off += int(SR * 0.17)
    return norm(add_silence(out, 0.02))

def sfx_defeat():
    # 下行/低沉小音，遗憾不恐怖：A4->E4->C4，柔和正弦
    seq = [("A4", 0.20), ("E4", 0.22), ("C4", 0.34)]
    out = np.zeros(int(SR * 0.86))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "sine", amp=0.7, attack=0.02, decay=0.22, release=0.06), seg)
        s += align(note(PENTA[name]*0.5, d, "sine", amp=0.3, attack=0.02, decay=0.22), seg)
        out[off:off+seg] += s
        off += int(SR * 0.24)
    return norm(add_silence(out, 0.02))

def sfx_button():
    # 极短"嗒"：高频小点击
    click = noise(0.02, 0.6)[:int(SR*0.02)]
    t = np.arange(len(click)) / SR
    click = click * np.exp(-t / 0.006)
    tick = note(1400, 0.02, "square", amp=0.4, attack=0.0005, decay=0.004)[:int(SR*0.02)]
    x = click + tick
    return norm(add_silence(x[:int(SR*0.05)], 0.003))

def sfx_wok():
    # 颠勺金属"哐当"：非谐分音簇 + 噪声撞击，短
    base = 520.0
    x = metallic([(base, 1.0), (base*1.34, 0.8), (base*1.97, 0.6),
                  (base*2.41, 0.4), (base*3.13, 0.25)], dur=0.22, amp=0.9, attack=0.001, decay=0.10)
    # 撞击噪声头
    nz = bp_sweep_noise(0.04, 2500, 900, amp=0.7)[:int(SR*0.04)]
    nz = nz * np.exp(-np.arange(len(nz)) / (SR*0.015))
    x = x + np.concatenate([nz, np.zeros(int(SR*0.22)-len(nz))])
    return norm(add_silence(x[:int(SR*0.24)], 0.005))


BUILDERS = {
    "sfx_shoot": sfx_shoot,
    "sfx_hit": sfx_hit,
    "sfx_kill": sfx_kill,
    "sfx_coin": sfx_coin,
    "sfx_dash": sfx_dash,
    "sfx_levelup": sfx_levelup,
    "sfx_unlock": sfx_unlock,
    "sfx_victory": sfx_victory,
    "sfx_defeat": sfx_defeat,
    "sfx_button": sfx_button,
    "sfx_wok": sfx_wok,
}

# 时长上限自检 (秒)
LIMITS = {
    "sfx_shoot": 0.18, "sfx_hit": 0.15, "sfx_kill": 0.30, "sfx_coin": 0.18,
    "sfx_dash": 0.32, "sfx_levelup": 0.50, "sfx_unlock": 0.60, "sfx_victory": 1.20,
    "sfx_defeat": 0.90, "sfx_button": 0.08, "sfx_wok": 0.25,
}

def main(names=None):
    os.makedirs(OUT, exist_ok=True)
    # 固定种子：噪声类音效（开火咔哒/命中/冲刺/颠勺/按钮）每次重生成都一致，
    # 只改某一个音效时不会把别的音效"顺手改掉"。
    np.random.seed(20261004)
    report = []
    for name, fn in BUILDERS.items():
        if names and name not in names:
            continue
        x = fn()
        path = os.path.join(OUT, name + ".ogg")
        sf.write(path, x, SR, format="OGG", subtype="VORBIS")
        info = sf.info(path)
        dur = info.duration
        peak = float(np.max(np.abs(x)))
        size = os.path.getsize(path)
        ok_dur = dur <= LIMITS[name] + 0.01
        ok_peak = peak <= PEAK
        report.append((name, dur, size, peak, info.channels, ok_dur, ok_peak))
    print("=== SYNTH REPORT ===")
    for name, dur, size, peak, ch, okd, okp in report:
        print(f"{name:14s} dur={dur:6.3f}s size={size:6d}B peak={peak:.3f} ch={ch} "
              f"dur_ok={okd} peak_ok={okp}")
    bad = [r for r in report if not (r[6] and r[5])]
    print("RESULT:", "ALL OK" if not bad else f"FAIL {bad}")

if __name__ == "__main__":
    # 可只重建个别音效：python3 art/sfx/synth_sfx.py sfx_coin sfx_hit
    main(sys.argv[1:] or None)
