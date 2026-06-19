import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
}

# 1. Test image/png on voices
url = "https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/voices/test_img.png"
headers["Content-Type"] = "image/png"
data = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82"

req = urllib.request.Request(url, data=data, headers=headers, method="POST")
try:
    with urllib.request.urlopen(req, timeout=10) as response:
        print("PNG on voices: SUCCESS", response.read().decode('utf-8'))
except Exception as e:
    print("PNG on voices: ERROR", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))

# 2. Test audio/webm on voices
url = "https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/voices/test_audio.webm"
headers["Content-Type"] = "audio/webm"
data = b"FAKE WEBM AUDIO DATA"
req = urllib.request.Request(url, data=data, headers=headers, method="POST")
try:
    with urllib.request.urlopen(req, timeout=10) as response:
        print("WEBM on voices: SUCCESS", response.read().decode('utf-8'))
except Exception as e:
    print("WEBM on voices: ERROR", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))
