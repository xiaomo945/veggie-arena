#!/usr/bin/env python3
"""
《萝卜突围 / TURNIP TROUBLE》音效合成器  v2（卡通可爱 / 舒缓 / 轻）
纯代码合成短音效 -> Ogg Vorbis (44100, mono, 峰值<=0.7)

设计目标（玩家反馈）：
  - 不要刺耳：禁用方波/锯齿波（它们的高次谐波是"炸耳"根源），只用正弦/三角。
  - 不要烦躁：整体降频、柔化起音（attack 拉长）、平滑指数衰减、低音量。
  - 不要频率太快：去掉所有"向上猛扫到 2~3kHz"的亮噪，最高成分压到 ~3.5kHz。
  - 卡通可爱：用五声音阶 + 轻柔的滑音（boop/toot），像玩具八音盒而非电子枪。

约束（不破坏既有调用方）：
  - 文件名 / 输出目录不变（Sfx.gd 的 key 与节流逻辑照旧）。
  - 每个音效时长 <= 旧 LIMITS（否则会与节流/混音假设冲突）。
  - 固定随机种子，保证每次重生成结果一致。
"""
import os
import sys
import numpy as np
import soundfile as sf

SR = 44100
PEAK = 0.70
# ⚠️ 本脚本就在 art/sfx/ 下，输出目录必须就是脚本所在目录。
OUT = os.path.dirname(os.path.abspath(__file__))

# 中式五声音阶频率表 (宫商角徵羽: C D E G A)，含跨八度
PENTA = {
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.00, "A4": 440.00,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00,
    "C6": 1046.50, "D6": 1174.66, "E6": 1318.51, "G6": 1567.98,
}

def norm(x, peak=PEAK):
    """限幅归一化，给 Ogg 解码过冲留余量，绝不削波"""
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
    if len(x) >= length:
        return x[:length]
    return np.concatenate([x, np.zeros(length - len(x))])

def soft_lp(x, cutoff=3500.0):
    """一阶低通，把 >cutoff 的高频毛刺磨掉（卡通/舒缓的关键一步）"""
    dt = 1.0 / SR
    rc = 1.0 / (2 * np.pi * cutoff)
    a = dt / (rc + dt)
    y = np.zeros(len(x))
    prev = 0.0
    for i in range(len(x)):
        prev = a * prev + (1.0 - a) * x[i]
        y[i] = prev
    return y

def note(freq, dur, wave="sine", amp=1.0, attack=0.010, decay=None, release=0.03):
    """带包络的单音（只接受 sine / triangle）"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    if wave == "sine":
        s = np.sin(2 * np.pi * freq * t)
    elif wave == "triangle":
        s = 2 * np.abs(2 * (freq * t - np.floor(freq * t + 0.5))) - 1
    else:
        raise ValueError("只用 sine/triangle，禁用 %s" % wave)
    s = s * amp
    dec = decay if decay is not None else dur * 0.7
    env = np.ones(n)
    a_n = int(SR * attack)
    if a_n > 0:
        env[:a_n] = np.linspace(0, 1, a_n)
    env = env * np.exp(-np.arange(n) / (SR * dec))
    rel_n = int(SR * release)
    if rel_n > 0:
        env[-rel_n:] *= np.linspace(1, 0, rel_n)
    return s * env

def glide(f0, f1, dur, wave="sine", amp=1.0, attack=0.010, decay=None):
    """轻柔滑音（卡通 boop/toot 的灵魂），频率随时间 f0->f1 平滑过渡"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    phase = 2 * np.pi * np.cumsum(np.linspace(f0, f1, n)) / SR
    s = np.sin(phase) if wave == "sine" else 2 * np.abs(2 * (phase / (2 * np.pi) - np.floor(phase / (2 * np.pi) + 0.5))) - 1
    s = s * amp
    dec = decay if decay is not None else dur * 0.75
    env = np.ones(n)
    a_n = int(SR * attack)
    if a_n > 0:
        env[:a_n] = np.linspace(0, 1, a_n)
    env = env * np.exp(-np.arange(n) / (SR * dec))
    return s * env

def noise(dur, amp=1.0):
    n = int(SR * dur)
    return np.random.randn(n) * amp

def soft_noise(dur, amp=1.0, f0=500.0, f1=300.0):
    """柔和的带通感噪声：低通后的噪声，频率偏低，绝不上探到刺耳区"""
    n = int(SR * dur)
    t = np.arange(n) / SR
    x = noise(dur, amp)
    # 用低频载频做"柔和的噗"而非尖噪
    carrier = np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f1, n)) / SR)
    env = np.exp(-t / (dur * 0.5))
    y = x * carrier * env
    return soft_lp(y, 1800.0)

def bell(freqs_amps, dur, amp=1.0, attack=0.004, decay=0.18):
    """钟磬/八音盒音：仅整数倍正弦分音（无方波锯齿），柔和快衰"""
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

# ---------- 13 个音效 ----------

def sfx_shoot():
    # 柔和"嘟"：中频正弦小幅下滑 + 极轻的二次泛音，毫无咔哒/尖刺
    s = glide(460, 340, 0.13, "sine", amp=0.55, attack=0.012, decay=0.10)
    s += 0.12 * glide(920, 680, 0.13, "sine", amp=0.55, attack=0.012, decay=0.08)
    s = soft_lp(s, 3000.0)
    return norm(add_silence(align(s, int(SR * 0.15)), 0.004))

def sfx_hit():
    # 软"啪"：低频闷击 + 一点点柔和带通噪声（频率压到 700->400，绝不上探）
    thud = note(150, 0.09, "sine", amp=0.85, attack=0.002, decay=0.05, release=0.02)
    nz = soft_noise(0.05, amp=0.22, f0=700, f1=400)
    x = thud + align(nz, int(SR * 0.09))
    return norm(add_silence(align(x, int(SR * 0.12)), 0.004))

def sfx_kill():
    # 可爱"啵"：低频上滑 boop + 极轻的柔噪爆点（不再扫到 2.5kHz）
    pop = glide(240, 430, 0.18, "sine", amp=0.55, attack=0.006, decay=0.13)
    pop[:int(SR*0.005)] = np.linspace(0, 1, int(SR*0.005)) * pop[:int(SR*0.005)]
    burst = soft_noise(0.05, amp=0.16, f0=500, f1=300)
    x = pop + align(burst, int(SR * 0.18))
    return norm(add_silence(align(x, int(SR * 0.20)), 0.004))

def sfx_hit_heavy():
    # 重击"咚"：更低更软的长衰减闷响（资源缺失则静默，这里补上）
    s = note(95, 0.22, "sine", amp=0.7, attack=0.003, decay=0.18, release=0.05)
    s2 = note(150, 0.20, "sine", amp=0.7, attack=0.003, decay=0.15)
    s = s + 0.4 * align(s2, len(s))
    s = soft_lp(s, 2200.0)
    return norm(add_silence(align(s, int(SR * 0.24)), 0.006))

def sfx_kill_boss():
    # Boss 爆：更低沉、更长的柔和中频"轰"，不是尖锐爆炸
    swell = glide(70, 120, 0.5, "sine", amp=0.6, attack=0.04, decay=0.4)
    s = swell + 0.5 * align(note(180, 0.45, "sine", amp=0.6, attack=0.02, decay=0.35), len(swell))
    s = s + 0.25 * align(soft_noise(0.18, amp=0.4, f0=400, f1=200), len(s))
    s = soft_lp(s, 2000.0)
    return norm(add_silence(align(s, int(SR * 0.55)), 0.01))

def sfx_coin():
    # 柔和铜钱"叮"：降调 + 整数倍泛音 + 慢起音 + 轻度低通，捡钱太频繁必须轻
    base = PENTA["A5"]  # 880.00
    x = bell([(base, 1.0), (base * 2.0, 0.28), (base * 3.0, 0.09)],
             dur=0.17, amp=0.8, attack=0.014, decay=0.10)
    L = int(SR * 0.17)
    x = align(x, L)
    x += align(note(base, 0.17, "sine", amp=0.30, attack=0.014, decay=0.09), L)
    x = soft_lp(x, 2600.0)
    x = norm(x) * 0.36
    return add_silence(x, 0.006)

def sfx_dash():
    # 柔和风声：频率压到 280->1300，远低于旧版 350->2600，听感是"呼"不是"嘶"
    n = int(SR * 0.30)
    t = np.arange(n) / SR
    x = noise(0.30, 0.8)
    carrier = np.sin(2 * np.pi * np.cumsum(np.linspace(280, 1300, n)) / SR)
    env = np.exp(-t / 0.12)
    y = x * carrier * env
    y = soft_lp(y, 2000.0)
    return norm(add_silence(align(y, int(SR * 0.31)), 0.005))

def sfx_levelup():
    # 上行"叮咚"（五声徵调），三角波本就柔和
    seq = [("G4", 0.10), ("D5", 0.10), ("G5", 0.16)]
    out = np.zeros(int(SR * 0.46))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "triangle", amp=0.7, attack=0.006, decay=0.12), seg)
        s += align(note(PENTA[name]*2, d*0.7, "sine", amp=0.15, attack=0.006, decay=0.08), seg)
        out[off:off+seg] += s
        off += int(SR * 0.13)
    s = soft_lp(out, 3200.0)
    return norm(add_silence(s, 0.01))

def sfx_unlock():
    # 成就"叮铃"双音（八音盒感），纯正弦整数倍分音，柔
    seq = [("E5", 0.14), ("A5", 0.22)]
    out = np.zeros(int(SR * 0.58))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(bell([(PENTA[name], 1.0), (PENTA[name]*2.0, 0.5), (PENTA[name]*3.0, 0.18)],
                       dur=d, amp=0.8, attack=0.004, decay=0.14), seg)
        s += align(note(PENTA[name], d, "triangle", amp=0.28, attack=0.005, decay=0.12), seg)
        out[off:off+seg] += s
        off += int(SR * 0.16)
    s = soft_lp(out, 3200.0)
    return norm(add_silence(s, 0.02))

def sfx_victory():
    # 上行琶音 C5 E5 G5 C6（大三和弦色彩），只用三角+正弦（去掉方波/锯齿的刺耳）
    seq = [("C5", 0.16), ("E5", 0.16), ("G5", 0.16), ("C6", 0.30)]
    out = np.zeros(int(SR * 1.10))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "triangle", amp=0.6, attack=0.012, decay=0.18, release=0.05), seg)
        s += align(note(PENTA[name]*2, d*0.6, "sine", amp=0.12, attack=0.012, decay=0.12), seg)
        s = soft_lp(s, 3000.0)
        out[off:off+seg] += s
        off += int(SR * 0.17)
    return norm(add_silence(out, 0.02))

def sfx_defeat():
    # 下行小音，遗憾不恐怖：A4->E4->C4，柔和正弦
    seq = [("A4", 0.20), ("E4", 0.22), ("C4", 0.34)]
    out = np.zeros(int(SR * 0.86))
    off = 0
    for name, d in seq:
        seg = int(SR * d)
        s = align(note(PENTA[name], d, "sine", amp=0.65, attack=0.02, decay=0.22, release=0.06), seg)
        s += align(note(PENTA[name]*0.5, d, "sine", amp=0.28, attack=0.02, decay=0.22), seg)
        out[off:off+seg] += s
        off += int(SR * 0.24)
    s = soft_lp(out, 2600.0)
    return norm(add_silence(s, 0.02))

def sfx_button():
    # 极轻"嗒"：中频正弦小下滑，无方波无噪声咔哒
    s = glide(760, 560, 0.03, "sine", amp=0.42, attack=0.002, decay=0.02)
    s = soft_lp(s, 3000.0)
    return norm(add_silence(align(s, int(SR * 0.05)), 0.003))

def sfx_wok():
    # 颠勺"哐"：低频非谐分音簇（压低基音与幅度）+ 柔和撞击头，短
    base = 360.0
    x = bell([(base, 1.0), (base*1.34, 0.7), (base*1.97, 0.5),
              (base*2.41, 0.32), (base*3.13, 0.2)], dur=0.22, amp=0.75, attack=0.002, decay=0.10)
    nz = soft_noise(0.04, amp=0.4, f0=900, f1=400)
    x = x + align(nz, int(SR * 0.22))
    x = soft_lp(x, 2400.0)
    return norm(add_silence(align(x, int(SR * 0.24)), 0.005))


BUILDERS = {
    "sfx_shoot": sfx_shoot,
    "sfx_hit": sfx_hit,
    "sfx_kill": sfx_kill,
    "sfx_hit_heavy": sfx_hit_heavy,
    "sfx_kill_boss": sfx_kill_boss,
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
    "sfx_shoot": 0.18, "sfx_hit": 0.15, "sfx_kill": 0.22, "sfx_hit_heavy": 0.26,
    "sfx_kill_boss": 0.60, "sfx_coin": 0.18, "sfx_dash": 0.32, "sfx_levelup": 0.50,
    "sfx_unlock": 0.60, "sfx_victory": 1.20, "sfx_defeat": 0.90, "sfx_button": 0.08,
    "sfx_wok": 0.25,
}

def main(names=None):
    os.makedirs(OUT, exist_ok=True)
    # 固定种子：噪声类音效每次重生成一致，只改某音效不会顺手改掉别的
    np.random.seed(20261009)
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
        # 高频能量占比（>4kHz 部分），用来客观验证"不刺耳"
        spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
        freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
        hi = np.sum(spec[freqs > 4000.0]) / (np.sum(spec) + 1e-9)
        size = os.path.getsize(path)
        ok_dur = dur <= LIMITS[name] + 0.01
        ok_peak = peak <= PEAK
        report.append((name, dur, size, peak, hi, info.channels, ok_dur, ok_peak))
    print("=== SYNTH REPORT (v2 卡通舒缓) ===")
    for name, dur, size, peak, hi, ch, okd, okp in report:
        print(f"{name:14s} dur={dur:6.3f}s size={size:6d}B peak={peak:.3f} "
              f"hi4k={hi*100:4.1f}% ch={ch} dur_ok={okd} peak_ok={okp}")
    bad = [r for r in report if not (r[7] and r[6])]
    print("RESULT:", "ALL OK" if not bad else f"FAIL {bad}")

if __name__ == "__main__":
    # 可只重建个别音效：python3 art/sfx/synth_sfx.py sfx_coin sfx_hit
    main(sys.argv[1:] or None)
