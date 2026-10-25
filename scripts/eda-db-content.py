import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
rows = con.execute("select id, url, image_data from project_images").fetchall()
for i, (rid, url, data) in enumerate(rows):
    print(rid, url, type(data), len(data) if data else 0)
    if data:
        out = rf"{sys.argv[2]}\imu-preview-{rid}.png"
        if isinstance(data, str):
            import base64
            try: data = base64.b64decode(data)
            except Exception: data = data.encode()
        open(out, "wb").write(data)
        print("  ->", out)
