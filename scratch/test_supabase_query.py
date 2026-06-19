import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj"
}

urls = [
    "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/profiles?select=*",
    "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/messages?select=*&limit=1"
]

for url in urls:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            print(f"URL: {url} - SUCCESS")
            print(response.read().decode('utf-8')[:200])
    except Exception as e:
        print(f"URL: {url} - ERROR:", e)
        if hasattr(e, 'read'):
            print("Details:", e.read().decode('utf-8'))
