"""Persist and render Shelf and Supabase credentials for this module."""
import base64
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

STATE = Path(os.environ["AGENT_STATE_DIR"])


def write_private(name, value):
    with tempfile.NamedTemporaryFile(dir=STATE, mode="w", delete=False) as stream:
        path = Path(stream.name)
        try:
            stream.write(value)
            stream.flush()
            os.replace(path, STATE / name)
        finally:
            path.unlink(missing_ok=True)


def token(secret, role):
    def encode(content):
        return base64.urlsafe_b64encode(content).rstrip(b"=")

    header = encode(b'{"alg":"HS256","typ":"JWT"}')
    payload = encode(json.dumps({"role": role, "iss": "supabase"}, separators=(",", ":")).encode())
    message = b".".join((header, payload))
    return b".".join((message, encode(hmac.digest(secret.encode(), message, hashlib.sha256)))).decode()


def secrets_file():
    return json.loads((STATE / "shelf-secrets.json").read_text())


def generate():
    if (STATE / "shelf-secrets.json").exists():
        return
    key = subprocess.run(
        ["openssl", "genrsa", "-traditional", "2048"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    der = subprocess.run(
        ["openssl", "rsa", "-traditional", "-outform", "DER"],
        input=key, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    values = {name: secrets.token_hex(32) for name in ("password", "jwt", "session", "invite")}
    values["saml"] = base64.b64encode(der).decode()
    write_private("shelf-secrets.json", json.dumps(values) + "\n")


def env(name, **values):
    for key, value in values.items():
        if any(character in str(value) for character in "\x00\r\n"):
            raise ValueError(f"Invalid line break in {key}")
    write_private(name + ".env", "".join(f"{key}={value}\n" for key, value in values.items()))
