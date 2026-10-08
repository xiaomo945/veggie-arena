#!/usr/bin/env python3
"""程序化合成「舒缓卡通轻音乐」背景乐，替换 art/audio/bgm_*.ogg。

设计原则（针对"比以前还难听 / 太吵太尖"的反馈）：
- 节奏放慢：菜单 72 / 战斗 84 / Boss 92 BPM（之前 112/128/150，太快太躁）。
- 音色柔和：主旋律用三角波 + 正弦，绝不用方波（方波是上一版"尖、刺耳"的元凶）；
  再叠一层轻柔的"音乐盒"高音（正弦短促）和一层暖垫（正弦长音），听感像轻音乐。
- 大调、简单悦耳的旋律 + 轻琶音，避免不和谐音程（阴森感来源）。
- 轻混响只增暖不增"鬼屋感"；整体增益压低（RMS 0.16~0.22），不轰头。
- 每段整数小节、每音从 0 起音 → 无缝 loop（Godot 里 loop=true 即可循环）。

输出：先写 16-bit PCM WAV，再用 ffmpeg 转 Ogg Vorbis（与 Bgm.gd 加载方式一致）。
"""
import numpy as np, subprocess, pathlib, math

SR = 44100

def midi_to_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))

def osc(wave, t, freq, phase=0.0):
    ph = 2 * np.pi * freq * t + phase
    if wave == "sine":
        return np.sin(ph)
    if wave == "tri":
        # 三角波：基频 + 少量奇次泛音，比纯三角更亮一点、但不刺耳
        return (2 / np.pi) * np.arcsin(np.sin(ph)) \
               + 0.08 * np.sin(3 * ph) + 0.04 * np.sin(5 * ph)
    return np.sin(ph)

def note(dur, freq, wave, gain, sr=SR, vibrato=0.0, soft=True):
    n = int(round(dur * sr))
    t = np.arange(n) / sr
    inst = osc(wave, t, freq, phase=2 * np.pi * vibrato * np.sin(2 * np.pi * 5 * t)) if vibrato > 0 \
        else osc(wave, t, freq)
    # 柔和包络：慢起音 + 平滑指数衰减到一段延音 + 尾段淡出，无爆音、不突兀
    a = int(0.020 * sr)
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    rel = int(0.12 * sr)
    env[-rel:] = np.linspace(1, 0, rel)
    body = np.exp(-1.1 * np.arange(n) / sr) if soft else np.exp(-2.0 * np.arange(n) / sr)
    env *= np.maximum(body, 0.45)        # 留一点延音，像轻音乐而不是木琴
    return inst * env * gain

def pad_note(dur, freq, gain, sr=SR):
    # 暖垫：正弦长音，慢起慢落，极轻，铺一层底
    n = int(round(dur * sr))
    t = np.arange(n) / sr
    inst = np.sin(2 * np.pi * freq * t)
    a = int(0.25 * sr); r = int(0.30 * sr)
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    env[-r:] = np.linspace(1, 0, r)
    return inst * env * gain

def render(bpm, seq, sr=SR):
    beat = 60.0 / bpm
    total = sum(max(d, 0.0001) for (_, d, *_) in seq) * beat
    out = np.zeros(int(round(total * sr)) + 8)
    pos = 0.0
    for item in seq:
        midi, d, wave, gain = item[0], item[1], item[2], item[3]
        vib = item[4] if len(item) > 4 else 0.0
        durs = d * beat
        s = note(durs, midi_to_freq(midi), wave, gain, sr, vib)
        i0 = int(round(pos * sr))
        out[i0:i0 + len(s)] += s
        pos += durs
    return out

def pad_render(bpm, seq, sr=SR):
    beat = 60.0 / bpm
    total = sum(max(d, 0.0001) for (_, d, *_) in seq) * beat
    out = np.zeros(int(round(total * sr)) + 8)
    pos = 0.0
    for midi, d, gain in seq:
        durs = d * beat
        s = pad_note(durs, midi_to_freq(midi), gain, sr)
        i0 = int(round(pos * sr))
        out[i0:i0 + len(s)] += s
        pos += durs
    return out

def mix(*tracks):
    n = max(len(x) for x in tracks)
    out = np.zeros(n)
    for x in tracks:
        out[:len(x)] += x
    return out

def soft_lowpass(x, cutoff=4200.0):
    # 一阶低通，柔化高频，去掉任何毛刺
    rc = 1.0 / (2 * np.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    y = np.zeros_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = y[i - 1] + a * (x[i] - y[i - 1])
    return y

def gentle_reverb(x, delay=0.12, fb=0.20, wet=0.20):
    # 短延迟混响：只增暖不增"阴森"
    out = x.copy()
    d = int(delay * SR)
    tap = np.zeros(len(x) + d)
    tap[:len(x)] = x
    for _ in range(3):
        out += wet * tap[d:] * fb
        tap[:-d] = tap[d:]
    return out

def normalize(x, peak=0.82):
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    return np.tanh(x * 1.05)        # 软限幅，防削波

def write_wav(path, x):
    xi = np.int16(np.clip(x, -1, 1) * 32767)
    import wave
    w = wave.open(str(path), "w")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(xi.tobytes())
    w.close()

def to_ogg(wav, ogg):
    subprocess.run(["ffmpeg", "-y", "-i", str(wav), "-c:a", "libvorbis",
                    "-q:a", "5", "-ar", "44100", str(ogg)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ---------------------------------------------------------------------------
# 三段旋律（慢、柔、大调、轻音乐）
# ---------------------------------------------------------------------------
def menu_track():
    # C 大调，72 BPM，轻松的村庄主题；音乐盒主旋律 + 暖垫 + 轻琶音
    lead = [
        (76, 1, "tri", 0.20, 5.0), (79, 1, "tri", 0.18, 5.0),
        (84, 1, "tri", 0.20, 5.0), (79, 1, "tri", 0.16, 5.0),
        (81, 1, "tri", 0.18, 5.0), (79, 1, "tri", 0.16, 5.0),
        (76, 1, "tri", 0.18, 5.0), (72, 2, "tri", 0.20, 5.0),
        (74, 1, "tri", 0.18, 5.0), (77, 1, "tri", 0.18, 5.0),
        (81, 1, "tri", 0.18, 5.0), (77, 1, "tri", 0.16, 5.0),
        (79, 1, "tri", 0.18, 5.0), (76, 1, "tri", 0.16, 5.0),
        (74, 1, "tri", 0.16, 5.0), (72, 2, "tri", 0.20, 5.0),
    ]
    bass = [(48, 4, "sine", 0.26), (43, 4, "sine", 0.24),
            (45, 4, "sine", 0.24), (41, 4, "sine", 0.24)]
    pad = [(60, 4, 0.05), (55, 4, 0.05), (57, 4, 0.05), (53, 4, 0.05)]
    pluck = [(88, 0.5, "sine", 0.07), (84, 0.5, "sine", 0.06),
             (88, 0.5, "sine", 0.07), (84, 0.5, "sine", 0.06),
             (88, 0.5, "sine", 0.07), (84, 0.5, "sine", 0.06),
             (88, 0.5, "sine", 0.07), (84, 0.5, "sine", 0.06)]
    return mix(render(72, lead), render(72, bass), pad_render(72, pad), render(72, pluck))

def battle_track():
    # 84 BPM，温柔推进；三角波主旋律带轻八分弹跳，仍是轻音乐味
    lead = [
        (72, 0.5, "tri", 0.16, 5.0), (76, 0.5, "tri", 0.15, 5.0),
        (79, 1, "tri", 0.16, 5.0), (76, 0.5, "tri", 0.14, 5.0),
        (74, 0.5, "tri", 0.15, 5.0), (77, 1, "tri", 0.16, 5.0),
        (81, 0.5, "tri", 0.15, 5.0), (79, 0.5, "tri", 0.14, 5.0),
        (72, 0.5, "tri", 0.16, 5.0), (76, 0.5, "tri", 0.15, 5.0),
        (79, 1, "tri", 0.16, 5.0), (77, 0.5, "tri", 0.14, 5.0),
        (76, 0.5, "tri", 0.15, 5.0), (74, 1, "tri", 0.16, 5.0),
        (72, 1, "tri", 0.16, 5.0), (72, 1, "tri", 0.16, 5.0),
    ]
    bass = [(48, 2, "sine", 0.24), (55, 2, "sine", 0.22),
            (57, 2, "sine", 0.22), (53, 2, "sine", 0.22),
            (48, 2, "sine", 0.24), (55, 2, "sine", 0.22),
            (57, 2, "sine", 0.22), (53, 2, "sine", 0.22)]
    pad = [(60, 4, 0.04), (55, 4, 0.04), (57, 4, 0.04), (53, 4, 0.04)]
    return mix(render(84, lead), render(84, bass), pad_render(84, pad))

def boss_track():
    # 92 BPM，稍饱满但仍柔和；加一层轻低音脉动，不刺耳
    lead = [
        (72, 0.5, "tri", 0.15, 5.5), (79, 0.5, "tri", 0.14, 5.5),
        (76, 1, "tri", 0.15, 5.5), (72, 0.5, "tri", 0.13, 5.5),
        (74, 0.5, "tri", 0.14, 5.5), (81, 1, "tri", 0.15, 5.5),
        (77, 0.5, "tri", 0.14, 5.5), (74, 0.5, "tri", 0.13, 5.5),
        (76, 0.5, "tri", 0.14, 5.5), (83, 0.5, "tri", 0.14, 5.5),
        (81, 1, "tri", 0.15, 5.5), (79, 0.5, "tri", 0.13, 5.5),
        (77, 0.5, "tri", 0.14, 5.5), (76, 1, "tri", 0.15, 5.5),
        (72, 1, "tri", 0.15, 5.5), (72, 1, "tri", 0.15, 5.5),
    ]
    bass = [(36, 2, "sine", 0.26), (43, 2, "sine", 0.24),
            (45, 2, "sine", 0.24), (41, 2, "sine", 0.24),
            (36, 2, "sine", 0.26), (43, 2, "sine", 0.24),
            (45, 2, "sine", 0.24), (41, 2, "sine", 0.24)]
    pad = [(60, 4, 0.04), (55, 4, 0.04), (57, 4, 0.04), (53, 4, 0.04)]
    pulse = [(48, 1, "sine", 0.05), (48, 1, "sine", 0.05),
             (48, 1, "sine", 0.05), (48, 1, "sine", 0.05),
             (48, 1, "sine", 0.05), (48, 1, "sine", 0.05),
             (48, 1, "sine", 0.05), (48, 1, "sine", 0.05)]
    return mix(render(92, lead), render(92, bass), pad_render(92, pad), render(92, pulse))

def main():
    out = pathlib.Path("art/audio")
    out.mkdir(parents=True, exist_ok=True)
    jobs = [("menu", menu_track), ("battle", battle_track), ("boss", boss_track)]
    for name, fn in jobs:
        raw = normalize(gentle_reverb(soft_lowpass(fn())))
        rms = float(np.sqrt(np.mean(raw ** 2)))
        wav = out / f"bgm_{name}.wav"
        ogg = out / f"bgm_{name}.ogg"
        write_wav(wav, raw)
        to_ogg(wav, ogg)
        wav.unlink()      # 中间产物不入库，只留 ogg
        print("✅ bgm_%s.ogg  (%.1fs, rms=%.3f)" % (name, len(raw) / SR, rms))

if __name__ == "__main__":
    main()
