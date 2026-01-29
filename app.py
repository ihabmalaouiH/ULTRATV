import subprocess
import threading
import time
import os
from flask import Flask

M3U8_URL = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"

# مفتاح Facebook من Render Environment
FB_STREAM_KEY = os.getenv("FB_KEY")

app = Flask(__name__)

@app.route("/")
def home():
    return "Facebook Streamer Running"

def run_ffmpeg():
    rtmp_url = f"rtmps://live-api-s.facebook.com:443/rtmp/{FB_STREAM_KEY}"

    command = [
        "ffmpeg",
        "-re",
        "-i", M3U8_URL,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-tune", "zerolatency",
        "-pix_fmt", "yuv420p",
        "-profile:v", "baseline",
        "-level", "3.1",
        "-g", "60",
        "-b:v", "2500k",
        "-maxrate", "2500k",
        "-bufsize", "5000k",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ar", "44100",
        "-f", "flv",
        "-tls_verify", "0",
        rtmp_url
    ]

    while True:
        print("Starting stream...")
        p = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in p.stdout:
            print(line.strip())
        time.sleep(5)

if __name__ == "__main__":
    threading.Thread(target=run_ffmpeg, daemon=True).start()
    app.run(host="0.0.0.0", port=10000)
