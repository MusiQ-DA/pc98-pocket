import json, subprocess, sys, time
TOKEN = [l.split(":",1)[1].strip() for l in open("/Users/hiroya/.config/gh/hosts.yml") if "oauth_token:" in l][0]
def resolve(host):
    for _ in range(6):
        out = subprocess.run(["dig","+short",host,"@1.1.1.1"],capture_output=True,text=True).stdout
        ips=[l.strip() for l in out.splitlines() if l.strip() and l.strip()[0].isdigit()]
        if ips: return ips[-1]
        time.sleep(2)
    return None
IP = resolve("api.github.com")
def api(path):
    p=subprocess.run(["curl","-sS","--resolve",f"api.github.com:443:{IP}",
        "-H",f"Authorization: Bearer {TOKEN}",f"https://api.github.com{path}"],
        capture_output=True,text=True)
    return json.loads(p.stdout)
deadline=time.time()+int(sys.argv[1]) if len(sys.argv)>1 else time.time()+2400
last=""
while time.time()<deadline:
    d=api("/repos/MusiQ-DA/pc98-pocket/actions/runs?per_page=1")
    r=d["workflow_runs"][0]
    line=f"run#{r['run_number']} [{r['status']}/{r['conclusion']}]"
    if line!=last:
        print(line, flush=True); last=line
    if r["status"]=="completed":
        jobs=api(r["jobs_url"].split("https://api.github.com")[1])
        for j in jobs.get("jobs",[]):
            print(f"job: {j['name']} -> {j['conclusion']}")
            for s in j.get("steps",[]):
                print(f"  {s['name']:40s} {s['conclusion']}")
        sys.exit(0 if r.get("conclusion")=="success" else 1)
    time.sleep(30)
print("TIMEOUT"); sys.exit(2)
