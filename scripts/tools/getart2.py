import json, os, subprocess, zipfile
from urllib.parse import urlparse
TOKEN = [l.split(":",1)[1].strip() for l in open("/Users/hiroya/.config/gh/hosts.yml") if "oauth_token:" in l][0]
def resolve(host):
    for _ in range(5):
        out = subprocess.run(["dig","+short",host,"@1.1.1.1"],capture_output=True,text=True).stdout
        ips=[l.strip() for l in out.splitlines() if l.strip() and l.strip()[0].isdigit()]
        if ips: return ips[-1]
    return None
def fetch(url, out=None):
    from urllib.parse import urlparse
    u=urlparse(url); ip=resolve(u.hostname)
    hdrf="/tmp/h.txt"; args=["curl","-sS","--resolve",f"{u.hostname}:443:{ip}",
        "-H",f"Authorization: Bearer {TOKEN}","-D",hdrf]
    if out: args+=["-o",out]
    args+=[url]
    p=subprocess.run(args,capture_output=True,text=True)
    code=0; loc=None
    for line in open(hdrf,errors="ignore"):
        if line.startswith("HTTP/"): code=int(line.split()[1])
        if line.lower().startswith("location:"): loc=line.split(":",1)[1].strip()
    return code, loc
code, _ = fetch("https://api.github.com/repos/MusiQ-DA/pc98-pocket/actions/artifacts/9988764055/zip")
code, loc = fetch("https://api.github.com/repos/MusiQ-DA/pc98-pocket/actions/artifacts/9988764055/zip")
u=urlparse(loc); ip=resolve(u.hostname)
subprocess.run(["curl","-sS","--resolve",f"{u.hostname}:443:{ip}","-L","-o","/tmp/art_diag.zip",loc],check=True)
z=zipfile.ZipFile("/tmp/art_diag.zip")
z.extractall("/Users/hiroya/repo/pc98-pocket/src/fpga/output_files")
print("extracted:", z.namelist())
