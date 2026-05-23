import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Content-Type": "text/plain"
}

buckets = ["avatars", "voices"]
for bucket in buckets:
    url = f"https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/{bucket}/dummy.txt"
    data = b"Hello, this is a test upload"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            html = response.read()
            print(f"Bucket {bucket} Upload Success:", json.loads(html.decode('utf-8')))
    except Exception as e:
        print(f"Bucket {bucket} Upload Error:", e)
        if hasattr(e, 'read'):
            print("Details:", e.read().decode('utf-8'))
