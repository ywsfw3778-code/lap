import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj"
}

url = "https://fetmbjnehfdtousenflp.supabase.co/storage/v1/bucket"
req = urllib.request.Request(url, headers=headers, method="GET")

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        html = response.read()
        print("Buckets:", json.dumps(json.loads(html.decode('utf-8')), indent=2))
except Exception as e:
    print("Error:", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))
