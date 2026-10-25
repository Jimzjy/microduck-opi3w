import sqlite3, sys, json
con = sqlite3.connect(sys.argv[1])
tabs = [r[0] for r in con.execute("select name from sqlite_master where type='table'")]
print("TABLES:", tabs)
for t in tabs:
    n = con.execute(f"select count(*) from '{t}'").fetchone()[0]
    print(f"-- {t}: {n} rows")
    cols = [c[1] for c in con.execute(f"pragma table_info('{t}')")]
    print("   cols:", cols)
