"""Copy every submission from Supabase into picks/week-XX/<name>.json.
Run by .github/workflows/backup-picks.yml. Files are never deleted, so a pick
removed from the site still has its last saved copy here."""
import json, os, re, sys, urllib.request

url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/submissions?select=*&order=week,name"
key = os.environ["SUPABASE_SERVICE_KEY"]
req = urllib.request.Request(url, headers={"apikey": key, "Authorization": "Bearer " + key})
rows = json.load(urllib.request.urlopen(req, timeout=30))

out = sys.argv[1]
for r in rows:
    for k in list(r):
        if "pin" in k.lower():
            r.pop(k)
    slug = re.sub(r"[^a-z0-9]+", "-", str(r.get("name", "")).lower()).strip("-") or "unnamed"
    d = os.path.join(out, "picks", "week-%02d" % int(r["week"]))
    os.makedirs(d, exist_ok=True)
    data = {"week": r["week"], "name": r.get("name"), "updated_at": r.get("updated_at"),
            "picks": r.get("picks")}
    data.update({k: v for k, v in r.items() if k not in data})
    with open(os.path.join(d, slug + ".json"), "w") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
print("backed up", len(rows), "submissions")
