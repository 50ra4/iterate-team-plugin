#!/usr/bin/env python3
"""通知音 WAV を生成する（追加依存なし・標準ライブラリ wave のみ）。

用途: Notification hook（scripts/notify-waiting.sh）が再生する短い通知音
`assets/notify.wav` を再現可能な形で生成する。
開発者が音源を作り直したいときに 1 度だけ実行する想定で、hook 経路では使わない
（hook は生成済みのコミット済み WAV を再生する）。

二音（880Hz → 1175Hz）の短いチャイム。44.1kHz / 16bit / mono / 約 0.24 秒。
フェードイン・アウトでクリックノイズを抑える。

使い方（プラグインルートで実行）:
    python3 scripts/gen-notify-wav.py [出力パス]
    (デフォルト出力先: assets/notify.wav)
"""

from __future__ import annotations

import math
import os
import struct
import sys
import wave

FRAMERATE = 44100
AMPLITUDE = 0.35  # 0.0〜1.0（耳障りにならない程度に抑える）
TONES = [(880.0, 0.12), (1174.66, 0.12)]  # (周波数 Hz, 長さ秒) A5 → D6
FADE_SEC = 0.008  # フェード長（クリックノイズ抑制）


def _samples() -> list[int]:
    out: list[int] = []
    for freq, dur in TONES:
        n = int(FRAMERATE * dur)
        fade = max(1, int(FRAMERATE * FADE_SEC))
        for i in range(n):
            env = 1.0
            if i < fade:
                env = i / fade
            elif i > n - fade:
                env = max(0.0, (n - i) / fade)
            value = AMPLITUDE * env * math.sin(2 * math.pi * freq * i / FRAMERATE)
            out.append(int(value * 32767))
    return out


def main() -> int:
    out_path = sys.argv[1] if len(sys.argv) > 1 else "assets/notify.wav"
    # dirname が空（カレントへのベアファイル名出力）でも makedirs が落ちないよう "." で代替。
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    frames = b"".join(struct.pack("<h", s) for s in _samples())
    with wave.open(out_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FRAMERATE)
        w.writeframes(frames)
    print(f"wrote {out_path} ({len(frames)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
