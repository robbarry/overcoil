#!/usr/bin/env python3
"""Overcoil-only Apple registration and local build tools; never uploads."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.robbarry.overcoil"


def credentials(env_file):
    names = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH")
    config = {key: os.environ[key] for key in names if os.environ.get(key)}
    if env_file.exists():
        for raw in env_file.read_text().splitlines():
            key, sep, value = raw.strip().partition("=")
            if sep and key in names:
                config.setdefault(key, value.strip().strip('"').strip("'"))
    if any(not config.get(key) for key in names):
        raise SystemExit("Provide ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH via environment or --env-file.")
    config["ASC_KEY_PATH"] = str(Path(config["ASC_KEY_PATH"]).expanduser().resolve())
    if not Path(config["ASC_KEY_PATH"]).is_file():
        raise SystemExit("Configured ASC private key file does not exist.")
    return config


def request(config, path, body=None):
    def b64(value):
        return base64.urlsafe_b64encode(value).rstrip(b"=").decode()

    now = int(time.time())
    header = {"alg": "ES256", "kid": config["ASC_KEY_ID"], "typ": "JWT"}
    payload = {"iss": config["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing = ".".join(b64(json.dumps(v).encode()) for v in (header, payload))
    key = serialization.load_pem_private_key(Path(config["ASC_KEY_PATH"]).read_bytes(), password=None)
    r, s = decode_dss_signature(key.sign(signing.encode(), ec.ECDSA(hashes.SHA256())))
    token = signing + "." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # No request headers or tokens in diagnostics.
        raise SystemExit(f"Apple API HTTP {error.code}: {error.read().decode()}") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "register", "simulator", "device", "archive"])
    parser.add_argument("--env-file", type=Path, default=ROOT / "ios/.env")
    args = parser.parse_args()
    config = credentials(args.env_file) if args.command != "simulator" else None
    if args.command in ("status", "register"):
        query = urllib.parse.urlencode({"filter[identifier]": BUNDLE})
        path = "/v1/bundleIds?" + query
        # Apple's identifier filter can return prefix matches (e.g. .devsim).
        def exact_records():
            return [r for r in request(config, path)["data"] if r["attributes"]["identifier"] == BUNDLE]

        records = exact_records()
        if args.command == "register" and not records:
            request(config, "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
                "identifier": BUNDLE, "name": "Overcoil", "platform": "IOS"
            }}})
            records = exact_records()
            if not records:
                raise SystemExit("Registration returned but read-back did not find Overcoil. Inspect before retrying.")
        if any(r["attributes"].get("seedId") != "3XLD352MG9" for r in records):
            raise SystemExit("Unexpected bundle seed ID; stop and verify account/team.")
        print(json.dumps({"bundleIds": records}, indent=2))
        query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE, "fields[apps]": "name,bundleId,sku"})
        print(json.dumps({"apps": request(config, "/v1/apps?" + query)["data"]}, indent=2))
        return
    subprocess.run(["xcodegen", "generate", "--spec", str(ROOT / "ios/project.yml")], check=True)
    command = ["xcodebuild", "-project", str(ROOT / "ios/Overcoil.xcodeproj"), "-scheme", "Overcoil",
               "-derivedDataPath", str(ROOT / ".build/DerivedData")]
    if args.command == "simulator":
        command += ["-destination", "generic/platform=iOS Simulator", "CODE_SIGNING_ALLOWED=NO", "build"]
    else:
        command += ["-destination", "generic/platform=iOS", "-allowProvisioningUpdates",
                    "-authenticationKeyPath", config["ASC_KEY_PATH"],
                    "-authenticationKeyID", config["ASC_KEY_ID"],
                    "-authenticationKeyIssuerID", config["ASC_ISSUER_ID"]]
        command += (["-archivePath", str(ROOT / ".build/Overcoil.xcarchive"), "archive"]
                    if args.command == "archive" else ["build"])
    raise SystemExit(subprocess.run(command).returncode)


if __name__ == "__main__":
    main()
