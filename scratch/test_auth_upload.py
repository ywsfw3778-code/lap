import urllib.request
import json
import random

headers = {
    "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
    "Content-Type": "application/json"
}

# 1. Try to sign up a temporary random user to get a valid JWT
email = f"temp_tester_{random.randint(1000, 9999)}@gmail.com"
password = "TestPassword123!"

signup_url = "https://fetmbjnehfdtousenflp.supabase.co/auth/v1/signup"
signup_data = {
    "email": email,
    "password": password
}

req_signup = urllib.request.Request(signup_url, data=json.dumps(signup_data).encode('utf-8'), headers=headers, method="POST")

try:
    with urllib.request.urlopen(req_signup, timeout=10) as resp:
        res = json.loads(resp.read().decode('utf-8'))
        access_token = res.get("access_token")
        print("SignUp Success. Access Token length:", len(access_token) if access_token else 0)
        
        if access_token:
            # Try uploading PNG to voices as the authenticated user
            upload_url = "https://fetmbjnehfdtousenflp.supabase.co/storage/v1/object/voices/test_auth_img.png"
            upload_headers = {
                "apikey": "sb_publishable_YFXi-x4HSyrfy_gnM5gLOQ_r3XkeNLj",
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "image/png"
            }
            data = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf\xa4q\x00\x00\x00\x00IEND\xaeB`\x82"
            
            req_upload = urllib.request.Request(upload_url, data=data, headers=upload_headers, method="POST")
            with urllib.request.urlopen(req_upload, timeout=10) as resp_u:
                print("Auth User Upload Success:", resp_u.read().decode('utf-8'))
except Exception as e:
    print("Error:", e)
    if hasattr(e, 'read'):
        print("Details:", e.read().decode('utf-8'))
