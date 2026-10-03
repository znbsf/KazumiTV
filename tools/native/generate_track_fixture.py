"""Generate the synthetic multi-track test asset. Requires an explicit ffmpeg executable."""
import argparse
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("ffmpeg", help="Path to ffmpeg with libx264 and AAC encoders")
args = parser.parse_args()
output = Path(__file__).resolve().parents[1] / "app/src/androidTest/assets/tracks-fixture.mp4"
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="kazumitv-tracks-") as scratch:
    subtitles = []
    for language, text in [("en", "ENGLISH FIXTURE"), ("ja", "JAPANESE FIXTURE")]:
        path = Path(scratch) / f"{language}.srt"
        path.write_text(f"1\n00:00:00,100 --> 00:00:15,900\n{text}\n", encoding="utf-8")
        subtitles.append(str(path))
    command = [args.ffmpeg, "-y", "-f", "lavfi", "-i", "testsrc2=size=640x480:rate=24",
        "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-i", subtitles[0], "-i", subtitles[1],
        "-map", "0:v", "-map", "1:a", "-map", "1:a", "-map", "2:s", "-map", "3:s",
        "-c:v", "libx264", "-preset", "fast", "-crf", "32", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-c:s", "mov_text", "-metadata:s:a:0", "language=eng",
        "-metadata:s:a:1", "language=jpn", "-metadata:s:s:0", "language=eng",
        "-metadata:s:s:1", "language=jpn", "-disposition:a:0", "default", "-disposition:a:1", "0",
        "-disposition:s:0", "default", "-disposition:s:1", "0", "-t", "16", str(output)]
    subprocess.run(command, check=True)
print(output)
