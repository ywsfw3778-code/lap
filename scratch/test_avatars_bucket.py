import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Content-Type": "image/png"
}

url = "https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/avatars/test_chat_attach.png"
data = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82"

req = urllib.request.Request(url, data=data, headers=headers, method="POST")

try:
    with urllib.request.urlopen(req, timeout=10) as response:
        print("Avatars upload test: SUCCESS", response.read().decode('utf-8'))
except Exception as e:
    print("Avatars upload test: ERROR", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))
