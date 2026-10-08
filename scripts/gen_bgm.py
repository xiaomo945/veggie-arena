#!/usr/bin/env python3
"""程序化合成「欢快卡通」背景乐，替换 art/audio/bgm_*.ogg。

针对"阴森 / 像死了 / 来回转音 / 不欢快"的反馈，这版彻底换思路：
- 绝不用颤音（vibrato）：上一版每音都带 5Hz 音高抖动，就是用户说的"来回转音"。
- 绝不用低频长音暖垫（pad）：那是"阴森底噪"的来源，整段去掉。
- 节奏明快：菜单 116 / 战斗 128 / Boss 122 BPM（之前 72/84/92 太慢像"死了"）。
- 旋律用 C 大调五声音阶（do-re-mi-sol-la），永远明亮、绝不出现小调色彩；
  乐句清晰、落回主音，不瞎绕。全大三和弦 I–IV–V–I 循环。
- 音色：三角波 + 正弦主旋律（干净不刺耳），叠加"音乐盒"式短促高音做卡通闪光；
  贝斯用"蹦嚓"节奏（oom-pah）撑起欢快律动。
- 包络短促跳跃（快起音 + 快速衰减，无长延音），听感像八音盒 / 卡通片而不是风琴。
- 不混响（混响增"空旷阴森感"）；只做极轻高切去毛刺。
- 每段整数小节、每音从拍点起音 → 无缝 loop。

输出：先写 16-bit PCM WAV，再用 ffmpeg 转 Ogg Vorbis（与 Bgm.gd 加载方式一致）。
"""
import numpy as np, subprocess, pathlib, math

SR = 44100

def midi_to_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))

def osc(wave, t, freq):
    ph = 2 * np.pi * freq * t
    if wave == "sine":
        return np.sin(ph)
    if wave == "tri":
        # 三角波基频 + 极少泛音，明亮但不刺耳
        return (2 / np.pi) * np.arcsin(np.sin(ph)) + 0.05 * np.sin(3 * ph)
    if wave == "square":
        # 方波只在极轻的"闪光"高音里用一点点，给卡通颗粒感，不喧宾夺主
        return np.where(np.sin(ph) >= 0, 1.0, -1.0)
    return np.sin(ph)

def note(dur, freq, wave, gain, decay=4.0, sr=SR):
    n = int(round(dur * sr))
    if n <= 0:
        return np.zeros(1)
    t = np.arange(n) / sr
    inst = osc(wave, t, freq)
    # 跳跃包络：5ms 快起音 + 指数衰减，无长延音（避免"阴森/嗡嗡"的拖尾）
    a = int(0.005 * sr)
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    env *= np.exp(-decay * t)
    return inst * env * gain

def render(bpm, seq, sr=SR):
    beat = 60.0 / bpm
    total = sum(max(d, 1e-4) for (_, d, *_) in seq) * beat
    out = np.zeros(int(round(total * sr)) + 8)
    pos = 0.0
    for item in seq:
        midi, d, wave, gain = item[0], item[1], item[2], item[3]
        dec = item[4] if len(item) > 4 else 4.0
        durs = d * beat
        s = note(durs, midi_to_freq(midi), wave, gain, dec, sr)
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

def soft_highcut(x, cutoff=8200.0):
    # 一阶低通，只去极高频毛刺，保留明亮感（cutoff 远高于上一版的 4200）
    rc = 1.0 / (2 * np.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    y = np.zeros_like(x)
    y[0] = x[0]
    for i in range(1, len(x)):
        y[i] = y[i - 1] + a * (x[i] - y[i - 1])
    return y

def normalize(x, peak=0.85):
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
# 欢快卡通旋律（C 大调五声音阶：72,74,76,79,81 = do re mi sol la）
# 乐句清晰、每两小节落回主音，不瞎绕。
# ---------------------------------------------------------------------------
MOTIF = [72, 76, 79, 81, 79, 76, 74, 72,   # do mi sol la sol mi re do
         74, 76, 79, 76, 72, 74, 76, 72]   # re mi sol mi do re mi do

# 每小节贝斯根音（全大三和弦 I–IV–V–I）：C F G C
ROOTS = [48, 53, 55, 48]

def build_track(bpm, bars, motif=MOTIF, roots=ROOTS, sparkle=True):
    half = 0.5   # 八分音符 = 半拍
    mel = []
    bass = []
    for bar in range(bars):
        root = roots[bar % len(roots)]
        for i in range(8):
            deg = motif[(bar * 8 + i) % len(motif)]
            mel.append((deg, half, "tri", 0.20, 4.0))
        # 贝斯 "蹦嚓"：第1拍根音，第3拍轻三和弦琶音（卡通律动）
        bass.append((root, half, "tri", 0.24, 6.0))
        bass.append((root, half, "tri", 0.0, 6.0))      # 第2拍留白
        bass.append((root, half, "tri", 0.09, 6.0))
        bass.append((root + 4, half, "tri", 0.09, 6.0))
        bass.append((root + 7, half, "tri", 0.09, 6.0))
        bass.append((root, half, "tri", 0.0, 6.0))
        bass.append((root, half, "tri", 0.0, 6.0))
        bass.append((root, half, "tri", 0.0, 6.0))
    tracks = [render(bpm, mel), render(bpm, bass)]
    if sparkle:
        # 高音"闪光"：每小节第1、3拍点一个高八度短音（方波极轻），像八音盒叮咚
        sp = []
        for bar in range(bars):
            for beat in (0, 2):
                deg = motif[(bar * 8 + beat * 2) % len(motif)] + 12
                sp.append((deg, half, "square", 0.05, 7.0))
                sp.append((deg, half, "square", 0.0, 7.0))
        tracks.append(render(bpm, sp))
    return mix(*tracks)

def menu_track():
    return build_track(116, 4)

def battle_track():
    # 战斗更带劲：同动机但更快，闪光照常
    return build_track(128, 4)

def boss_track():
    # Boss 稍稳但仍欢乐明亮（不恐怖）：中等速度
    return build_track(122, 4)

def main():
    out = pathlib.Path("art/audio")
    out.mkdir(parents=True, exist_ok=True)
    jobs = [("menu", menu_track), ("battle", battle_track), ("boss", boss_track)]
    for name, fn in jobs:
        raw = normalize(soft_highcut(fn()))
        rms = float(np.sqrt(np.mean(raw ** 2)))
        wav = out / f"bgm_{name}.wav"
        ogg = out / f"bgm_{name}.ogg"
        write_wav(wav, raw)
        to_ogg(wav, ogg)
        wav.unlink()      # 中间产物不入库，只留 ogg
        print("✅ bgm_%s.ogg  (%.1fs, rms=%.3f)" % (name, len(raw) / SR, rms))

if __name__ == "__main__":
    main()
