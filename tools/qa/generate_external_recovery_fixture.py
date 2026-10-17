"""Create local, synthetic external-track recovery inputs; starts no server.

Usage: python tools/qa/generate_external_recovery_fixture.py FFMPEG EMPTY_OUTPUT_DIR
Requires ffmpeg MJPEG encoder. Video flashes white and audio beeps for the first
100 ms of each second. This is a timing reference, not proof of device AV sync.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import math
import struct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ffmpeg")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("Output directory must be empty; existing evidence is preserved")
    video = output / "sample.mkv"
    subprocess.run([
        args.ffmpeg, "-nostdin", "-n", "-f", "lavfi", "-i",
        "color=black:s=640x360:r=30,drawbox=color=white:t=fill:enable='lt(mod(t,1),0.1)'",
        "-t", "40", "-an", "-c:v", "mjpeg", "-q:v", "5",
        "-threads", "1", str(video),
    ], check=True, timeout=120)
    for name, frequency in [("external-a.wav", 440), ("external-b.wav", 880)]:
        with wave.open(str(output / name), "wb") as audio:
            audio.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
            for second in range(40):
                audio.writeframes(b"".join(struct.pack("<h", int(
                    4096 * math.sin(2 * math.pi * frequency * i / 48000)
                ) if i < 4800 else 0) for i in range(48000)))
    for label in ["A", "B"]:
        (output / f"external-{label.lower()}.srt").write_text("\n".join(
            f"{second + 1}\n00:00:{second:02d},000 --> 00:00:{second:02d},900\n"
            f"EXTERNAL {label} SECOND {second:02d}\n"
            for second in range(40)), encoding="utf-8")
    files = {p.name: {"bytes": p.stat().st_size,
             "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
             for p in sorted(output.iterdir())}
    (output / "manifest.json").write_text(json.dumps({
        "synthetic": True, "duration_seconds": 40,
        "video": "MJPEG; no embedded audio or subtitles",
        "pulse": "white flash + 100ms sine pulse at integer seconds",
        "files": files,
        "limits": "Native decoder support and actual speaker/display sync require device observation."
    }, indent=2), encoding="utf-8")
    print(output / "manifest.json")


if __name__ == "__main__":
    main()
