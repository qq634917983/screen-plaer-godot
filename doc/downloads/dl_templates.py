import concurrent.futures as cf
import os
import sys
import urllib.request

URL = "https://gh-proxy.com/https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
OUT = "doc/downloads/Godot_v4.7.2-stable_export_templates.tpz"
TOTAL = 1281349702
PARTS = 16
CHUNK = 4 * 1024 * 1024

def fetch(part):
    per = TOTAL // PARTS + 1
    start = part * per
    end = min(start + per, TOTAL) - 1
    if start >= TOTAL:
        return part, b""
    expected = end - start + 1
    for attempt in range(5):
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
            buf = bytearray()
            with urllib.request.urlopen(req, timeout=120) as r:
                while True:
                    data = r.read(CHUNK)
                    if not data:
                        break
                    buf += data
                    if len(buf) >= expected:
                        break
            if len(buf) == expected:
                return part, bytes(buf)
            if len(buf) > expected:
                # 服务器忽略 Range 返回全文（从 0 开始），切片即所求
                return part, bytes(buf[start:start + expected]) if len(buf) >= start + expected else bytes(buf[:expected])
            print(f"part {part} short read {len(buf)}/{expected}, retry {attempt + 1}", flush=True)
        except Exception as e:
            print(f"part {part} error {e}, retry {attempt + 1}", flush=True)
    raise RuntimeError(f"part {part} failed after retries")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
results = [None] * PARTS
done_bytes = 0
with cf.ThreadPoolExecutor(max_workers=PARTS) as ex:
    futs = [ex.submit(fetch, i) for i in range(PARTS)]
    for f in cf.as_completed(futs):
        part, data = f.result()
        results[part] = data
        done_bytes += len(data)
        print(f"part {part} done ({len(data)} bytes), total {done_bytes}/{TOTAL}", flush=True)

with open(OUT, "wb") as f:
    for d in results:
        f.write(d)
actual = os.path.getsize(OUT)
print(f"FINISHED size={actual} expected={TOTAL} match={actual == TOTAL}", flush=True)
sys.exit(0 if actual == TOTAL else 1)
