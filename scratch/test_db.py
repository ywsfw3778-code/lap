import urllib.request
import json

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Authorization": "Bearer sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

# We need a valid sender_id and receiver_id. Let's fetch some profiles first to get valid IDs!
url_profiles = "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/profiles?limit=2"
req_p = urllib.request.Request(url_profiles, headers=headers, method="GET")

try:
    with urllib.request.urlopen(req_p, timeout=10) as resp:
        profiles = json.loads(resp.read().decode('utf-8'))
        print("Found profiles:", [p.get("id") for p in profiles])
        if len(profiles) >= 2:
            sender_id = profiles[0]["id"]
            receiver_id = profiles[1]["id"]
            
            # Test insert image payload
            url_msg = "https://fetmbjnehfdtousenflp.supabase.co/rest/v1/messages"
            payload = {
                "sender_id": sender_id,
                "receiver_id": receiver_id,
                "content": "[image]https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/public/voices/test_img.png"
            }
            req_m = urllib.request.Request(url_msg, data=json.dumps(payload).encode('utf-8'), headers=headers, method="POST")
            with urllib.request.urlopen(req_m, timeout=10) as resp_m:
                print("Insert SUCCESS:", resp_m.read().decode('utf-8'))
        else:
            print("Not enough profiles to test insert.")
except Exception as e:
    print("Database test error:", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))
