#!/usr/bin/env python3
"""Seed demo members into the Firebase project.

Creates Firebase Auth email/password accounts via the public REST API and writes
each member's own profile doc (members/{uid}) using that member's ID token, so
the normal firestore.rules apply. Safe to re-run: existing accounts are signed in
and their profile is rewritten.

Usage: python3 tool/seed_members.py
"""
import json
import urllib.error
import urllib.request
from datetime import datetime, timezone

API_KEY = "AIzaSyAPz91sihhQVXQ0eMqdqUXehkTrHs16CNg"
PROJECT = "community-dd944"
PASSWORD = "community123"

MEMBERS = [
    ("Alice Johnson", "555-0101"),
    ("Brian Lee", "555-0102"),
    ("Carmen Diaz", "555-0103"),
    ("David Kim", "555-0104"),
    ("Emma Brown", "555-0105"),
    ("Farid Haddad", "555-0106"),
    ("Grace Chen", "555-0107"),
    ("Hector Ruiz", "555-0108"),
    ("Isabel Moreau", "555-0109"),
    ("Jamal Wright", "555-0110"),
    ("Keiko Tanaka", "555-0111"),
    ("Liam O'Connor", "555-0112"),
]


def post(url, body, token=None, method="POST"):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return {"error": json.load(e)["error"]}


def auth(email):
    base = "https://identitytoolkit.googleapis.com/v1/accounts"
    body = {"email": email, "password": PASSWORD, "returnSecureToken": True}
    r = post(f"{base}:signUp?key={API_KEY}", body)
    if "error" in r and r["error"]["message"] == "EMAIL_EXISTS":
        r = post(f"{base}:signInWithPassword?key={API_KEY}", body)
        r["existed"] = True
    return r


def main():
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ok = 0
    for name, phone in MEMBERS:
        email = name.split()[0].lower() + "@example.com"
        a = auth(email)
        if "error" in a:
            print(f"FAIL auth  {email}: {a['error']['message']}")
            continue
        url = (f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
               f"/databases/(default)/documents/members/{a['localId']}")
        doc = {"fields": {
            "name": {"stringValue": name},
            "email": {"stringValue": a["email"]},
            "phone": {"stringValue": phone},
            "createdAt": {"timestampValue": now},
        }}
        w = post(url, doc, token=a["idToken"], method="PATCH")
        if "error" in w:
            print(f"FAIL write {email}: {w['error']['message']}")
            continue
        ok += 1
        print(f"{'exists ' if a.get('existed') else 'created'} {email:24} {name}")
    print(f"\n{ok}/{len(MEMBERS)} members ready. Password for all: {PASSWORD}")


if __name__ == "__main__":
    main()
