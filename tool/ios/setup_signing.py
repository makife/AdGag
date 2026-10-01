"""One-time iOS signing setup for the TestFlight workflow — no Mac needed.

Talks to the App Store Connect API with an API key and:
  1. registers the bundle id (com.ergan.adgag) if it isn't yet,
  2. creates an Apple Distribution certificate from a key generated HERE
     (reused on later runs — the key never leaves this machine except as the
     .p12 GitHub secret),
  3. (re)creates the App Store provisioning profile "AdGag App Store CI"
     (the name ios/Runner.xcodeproj's Release config signs with),
  4. writes every GitHub secret the iOS workflow needs to
     ios/signing/secrets/<NAME>.txt (gitignored).

Usage:
  python tool/ios/setup_signing.py --p8 path/to/AuthKey_ABC123.p8 --issuer-id <uuid>

The API key needs the Admin role (creating certificates/profiles). Rerun any
time; it reuses the certificate and only makes a fresh profile (needed after
the certificate changes or a profile expires — profiles last a year).
"""

import argparse
import base64
import os
import plistlib
import re
import secrets
import sys
import time
from pathlib import Path

import jwt
import requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.ergan.adgag"
APP_NAME = "AdGag"
PROFILE_NAME = "AdGag App Store CI"

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ios" / "signing"


class Api:
    def __init__(self, key_id: str, issuer_id: str, p8: str):
        self.key_id, self.issuer_id, self.p8 = key_id, issuer_id, p8

    def _headers(self):
        now = int(time.time())
        token = jwt.encode(
            {"iss": self.issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            self.p8,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )
        return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    def call(self, method: str, path: str, **kw):
        r = requests.request(method, API + path, headers=self._headers(), timeout=60, **kw)
        if r.status_code >= 400:
            sys.exit(f"App Store Connect API {method} {path} -> HTTP {r.status_code}\n{r.text}")
        return r.json() if r.text else {}


def ensure_bundle_id(api: Api) -> str:
    found = api.call("GET", "/bundleIds", params={"filter[identifier]": BUNDLE_ID, "limit": 200})
    for item in found["data"]:
        if item["attributes"]["identifier"] == BUNDLE_ID:
            print(f"Bundle id {BUNDLE_ID} already registered.")
            return item["id"]
    created = api.call("POST", "/bundleIds", json={"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID, "name": APP_NAME, "platform": "IOS"}}})
    print(f"Registered bundle id {BUNDLE_ID}.")
    return created["data"]["id"]


def ensure_certificate(api: Api):
    key_path, cert_path, id_path = OUT / "dist_key.pem", OUT / "dist_cert.cer", OUT / "dist_cert_id.txt"
    if key_path.exists() and cert_path.exists() and id_path.exists():
        cert_id = id_path.read_text().strip()
        r = requests.get(f"{API}/certificates/{cert_id}", headers=api._headers(), timeout=60)
        if r.status_code == 200:
            print("Reusing the existing distribution certificate.")
            key = serialization.load_pem_private_key(key_path.read_bytes(), None)
            return cert_id, key, x509.load_der_x509_certificate(cert_path.read_bytes())
        print("Saved certificate no longer exists at Apple (revoked/expired) — making a new one.")

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "AdGag CI Distribution")]))
           .sign(key, hashes.SHA256()))
    created = api.call("POST", "/certificates", json={"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION",
        "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode()}}})
    cert_id = created["data"]["id"]
    der = base64.b64decode(created["data"]["attributes"]["certificateContent"])
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                           serialization.NoEncryption()))
    cert_path.write_bytes(der)
    id_path.write_text(cert_id)
    print("Created a new Apple Distribution certificate.")
    return cert_id, key, x509.load_der_x509_certificate(der)


def make_profile(api: Api, bundle_db_id: str, cert_id: str) -> bytes:
    old = api.call("GET", "/profiles", params={"filter[name]": PROFILE_NAME, "limit": 200})
    for item in old["data"]:
        if item["attributes"]["name"] == PROFILE_NAME:
            api.call("DELETE", f"/profiles/{item['id']}")
            print("Deleted the previous profile of the same name.")
    created = api.call("POST", "/profiles", json={"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_db_id}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
        }}})
    print(f"Created provisioning profile '{PROFILE_NAME}'.")
    return base64.b64decode(created["data"]["attributes"]["profileContent"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--p8", required=True, help="AuthKey_<KEYID>.p8 downloaded from App Store Connect")
    ap.add_argument("--issuer-id", required=True, help="Issuer ID shown above the keys list")
    ap.add_argument("--key-id", help="defaults to the <KEYID> in the .p8 file name")
    a = ap.parse_args()

    p8_text = Path(a.p8).read_text()
    key_id = a.key_id or (re.search(r"AuthKey_([A-Z0-9]+)\.p8$", a.p8) or sys.exit("Pass --key-id")).group(1)
    OUT.mkdir(parents=True, exist_ok=True)
    api = Api(key_id, a.issuer_id, p8_text)

    bundle_db_id = ensure_bundle_id(api)
    cert_id, key, cert = ensure_certificate(api)
    profile = make_profile(api, bundle_db_id, cert_id)
    (OUT / "AdGag_App_Store_CI.mobileprovision").write_bytes(profile)
    plist = plistlib.loads(profile[profile.index(b"<?xml"):profile.index(b"</plist>") + len(b"</plist>")])
    team_id = plist["TeamIdentifier"][0]

    password = secrets.token_urlsafe(24)
    p12 = pkcs12.serialize_key_and_certificates(
        b"AdGag CI Distribution", key, cert, None,
        # Legacy 3DES/SHA1 encryption: macOS `security import` reliably reads it.
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode()))
    (OUT / "dist.p12").write_bytes(p12)

    sec = OUT / "secrets"
    sec.mkdir(exist_ok=True)
    values = {
        "IOS_DIST_CERT_P12_BASE64": base64.b64encode(p12).decode(),
        "IOS_DIST_CERT_PASSWORD": password,
        "IOS_PROVISION_PROFILE_BASE64": base64.b64encode(profile).decode(),
        "APPLE_TEAM_ID": team_id,
        "ASC_KEY_ID": key_id,
        "ASC_ISSUER_ID": a.issuer_id,
        "ASC_KEY_P8": p8_text.strip(),
    }
    for name, value in values.items():
        (sec / f"{name}.txt").write_text(value)
    print(f"\nTeam ID: {team_id}, profile expires {plist['ExpirationDate']:%Y-%m-%d}")
    print(f"GitHub secrets written to {sec} (one file per secret; the file name is the secret name):")
    for name in values:
        print("  " + name)


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
