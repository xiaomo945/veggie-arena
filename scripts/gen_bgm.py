#!/usr/bin/env python3
"""程序化合成「可爱卡通」背景乐，替换 art/audio/bgm_*.ogg。

设计原则（针对"原乐阴森/像闹鬼"的反馈）：
- 全部用【大调】音阶，避免小调/不和谐音程（阴森感主要来自这里）。
- 主旋律用三角波 + 一点方波泛音（明亮、像八位机/卡通），贝斯用正弦（干净），
  再叠一层短促拨弦（pluck）增加"弹跳/俏皮"感。
- 轻混响（几声低增益延迟）只为了暖一点，不做长尾（长混响 + 小调才像鬼屋）。
- 每段是整数小节、每音从 0 起音 → 整段可无缝 loop（Godot 里 loop=true 即可循环）。

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
        # 三角波：基频 + 少量奇次泛音，比纯三角更亮一点
        return (2 / np.pi) * np.arcsin(np.sin(ph)) \
               + 0.10 * np.sin(3 * ph) + 0.05 * np.sin(5 * ph)
    if wave == "square":
        return np.sign(np.sin(ph)) + 0.12 * np.sin(3 * ph)
    return np.sin(ph)

def note(dur, freq, wave, gain, sr=SR, vibrato=0.0):
    n = int(round(dur * sr))
    t = np.arange(n) / sr
    if vibrato > 0:
        inst = osc(wave, t, freq, phase=2 * np.pi * vibrato * np.sin(2 * np.pi * 5 * t))
    else:
        inst = osc(wave, t, freq)
    # ADSR 简化：快起音、指数衰减到 sustain、尾段淡出，避免爆音
    a = int(0.012 * sr)
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    rel = int(0.08 * sr)
    env[-rel:] = np.linspace(1, 0, rel)
    # 整体轻微衰减，让音与音之间留呼吸
    body = np.exp(-1.6 * np.arange(n) / sr)
    env *= np.maximum(body, 0.35)
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

def mix(*tracks):
    n = max(len(x) for x in tracks)
    out = np.zeros(n)
    for x in tracks:
        out[:len(x)] += x
    return out

def soft_lowpass(x, cutoff=5200.0):
    # 一阶低通，去掉方波高频毛刺，听感更柔和
    rc = 1.0 / (2 * np.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    y = np.zeros_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = y[i - 1] + a * (x[i] - y[i - 1])
    return y

def gentle_reverb(x, delay=0.13, fb=0.18, wet=0.22):
    # 短延迟混响，只增暖不增"阴森"
    out = x.copy()
    d = int(delay * SR)
    tap = np.zeros(len(x) + d)
    tap[:len(x)] = x
    for _ in range(3):
        out += wet * tap[d:] * fb
        tap[:-d] = tap[d:]
    return out

def normalize(x, peak=0.92):
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    return np.tanh(x * 1.05)  # 软限幅，防削波

def write_wav(path, x):
    xi = np.int16(np.clip(x, -1, 1) * 32767)
    import wave
    w = wave.open(str(path), "w")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(xi.tobytes())
    w.close()

def to_ogg(wav, ogg):
    subprocess.run(["ffmpeg", "-y", "-i", str(wav), "-c:a", "libvorbis",
                    "-q:a", "6", "-ar", "44100", str(ogg)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ---------------------------------------------------------------------------
# 三段旋律（大调、俏皮）
# ---------------------------------------------------------------------------
def menu_track():
    # C 大调，112 BPM，像轻松的村庄主题；每 2 拍一个贝斯根音 C-G-Am-F
    lead = [
        (72, 0.5, "tri", 0.34, 5.5), (76, 0.5, "tri", 0.30, 5.5),
        (79, 0.5, "tri", 0.34, 5.5), (76, 0.5, "tri", 0.28, 5.5),
        (74, 0.5, "tri", 0.32, 5.5), (77, 0.5, "tri", 0.30, 5.5),
        (81, 0.5, "tri", 0.34, 5.5), (77, 0.5, "tri", 0.28, 5.5),
        (72, 0.5, "tri", 0.34, 5.5), (76, 0.5, "tri", 0.30, 5.5),
        (79, 0.5, "tri", 0.34, 5.5), (84, 0.5, "tri", 0.30, 5.5),
        (79, 0.5, "tri", 0.30, 5.5), (76, 0.5, "tri", 0.28, 5.5),
        (74, 0.5, "tri", 0.30, 5.5), (72, 1.0, "tri", 0.32, 5.5),
    ]
    bass = [(48, 2, "sine", 0.30), (43, 2, "sine", 0.28),
            (45, 2, "sine", 0.28), (41, 2, "sine", 0.28)]
    pluck = [(84, 0.5, "tri", 0.16), (86, 0.5, "tri", 0.14),
             (88, 0.5, "tri", 0.16), (86, 0.5, "tri", 0.14)]
    return mix(render(112, lead), render(112, bass), render(112, pluck))

def battle_track():
    # 128 BPM，推进感；根音八分驱动 C-G-Am-F
    lead = [
        (72, 0.5, "square", 0.20, 6.0), (79, 0.5, "square", 0.20, 6.0),
        (76, 0.5, "square", 0.20, 6.0), (72, 0.5, "square", 0.20, 6.0),
        (74, 0.5, "square", 0.20, 6.0), (81, 0.5, "square", 0.20, 6.0),
        (77, 0.5, "square", 0.20, 6.0), (74, 0.5, "square", 0.20, 6.0),
        (72, 0.5, "square", 0.20, 6.0), (79, 0.5, "square", 0.20, 6.0),
        (84, 0.5, "square", 0.20, 6.0), (79, 0.5, "square", 0.20, 6.0),
        (77, 0.5, "square", 0.20, 6.0), (76, 0.5, "square", 0.20, 6.0),
        (74, 0.5, "square", 0.20, 6.0), (72, 1.0, "square", 0.22, 6.0),
    ]
    bass = [(48, 1, "sine", 0.30), (55, 1, "sine", 0.28),
            (57, 1, "sine", 0.28), (53, 1, "sine", 0.28),
            (48, 1, "sine", 0.30), (55, 1, "sine", 0.28),
            (57, 1, "sine", 0.28), (53, 1, "sine", 0.28)]
    pluck = [(84, 0.5, "tri", 0.14), (84, 0.5, "tri", 0.14),
             (84, 0.5, "tri", 0.14), (84, 0.5, "tri", 0.14),
             (86, 0.5, "tri", 0.13), (86, 0.5, "tri", 0.13),
             (86, 0.5, "tri", 0.13), (86, 0.5, "tri", 0.13)]
    return mix(render(128, lead), render(128, bass), render(128, pluck))

def boss_track():
    # 150 BPM，更带劲但仍是大调；八度跳进制造紧张但不阴森
    lead = [
        (84, 0.5, "square", 0.20, 6.5), (72, 0.5, "square", 0.20, 6.5),
        (79, 0.5, "square", 0.20, 6.5), (67, 0.5, "square", 0.20, 6.5),
        (81, 0.5, "square", 0.20, 6.5), (69, 0.5, "square", 0.20, 6.5),
        (76, 0.5, "square", 0.20, 6.5), (64, 0.5, "square", 0.20, 6.5),
        (84, 0.5, "square", 0.20, 6.5), (79, 0.5, "square", 0.20, 6.5),
        (86, 0.5, "square", 0.20, 6.5), (81, 0.5, "square", 0.20, 6.5),
        (88, 0.5, "square", 0.20, 6.5), (83, 0.5, "square", 0.20, 6.5),
        (79, 0.5, "square", 0.20, 6.5), (72, 1.0, "square", 0.22, 6.5),
    ]
    bass = [(36, 1, "sine", 0.32), (43, 1, "sine", 0.30),
            (45, 1, "sine", 0.30), (41, 1, "sine", 0.30),
            (36, 1, "sine", 0.32), (43, 1, "sine", 0.30),
            (45, 1, "sine", 0.30), (41, 1, "sine", 0.30)]
    pluck = [(96, 0.5, "tri", 0.12), (96, 0.5, "tri", 0.12),
             (96, 0.5, "tri", 0.12), (96, 0.5, "tri", 0.12),
             (98, 0.5, "tri", 0.11), (98, 0.5, "tri", 0.11),
             (98, 0.5, "tri", 0.11), (98, 0.5, "tri", 0.11)]
    return mix(render(150, lead), render(150, bass), render(150, pluck))

def main():
    out = pathlib.Path("art/audio")
    out.mkdir(parents=True, exist_ok=True)
    jobs = [("menu", menu_track), ("battle", battle_track), ("boss", boss_track)]
    for name, fn in jobs:
        raw = normalize(gentle_reverb(soft_lowpass(fn())))
        # 拼接 2 倍长度：每音都从 0 起音，首尾是静音，拼接后依然无缝 loop，
        # 避免 4 秒短循环一听就重复。
        raw = np.concatenate([raw, raw])
        rms = float(np.sqrt(np.mean(raw ** 2)))
        wav = out / f"bgm_{name}.wav"
        ogg = out / f"bgm_{name}.ogg"
        write_wav(wav, raw)
        to_ogg(wav, ogg)
        wav.unlink()  # 中间产物不入库，只留 ogg
        print("✅ bgm_%s.ogg  (%.1fs, rms=%.3f)" % (name, len(raw) / SR, rms))

if __name__ == "__main__":
    main()
