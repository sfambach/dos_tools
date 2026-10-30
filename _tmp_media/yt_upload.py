#!/usr/bin/env python3
"""Upload videos to Stefan's YouTube channel without an AI in the loop.

Usage:
  yt_upload.py auth   -           one-time browser login, stores the token in the GNOME keyring
  yt_upload.py upload <dir>       upload every row of <dir>/videos.csv that has no youtube_id yet
  yt_upload.py check  -           read-only test: prints the channel name

videos.csv (';'-separated, UTF-8):
  quelle;titel;beschreibung;tags;youtube_id
  quelle  absolute path of the video file
  tags    comma-separated

Uploads from an unverified API project stay private until they are made public in YouTube Studio.
Needs: google-api-python-client google-auth-oauthlib (in tools/.venv).
Client secret: tools/yt_client_secret.json (from Google Cloud, never commit it).
"""
import csv, json, os, subprocess, sys

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/youtube.upload", "https://www.googleapis.com/auth/youtube.readonly"]
CLIENT_SECRET = os.path.join(os.path.dirname(os.path.abspath(__file__)), "yt_client_secret.json")
KEYRING = ["service", "fambach-yt", "user", "token"]
FIELDS = ["quelle", "titel", "beschreibung", "tags", "youtube_id"]


def store_token(creds):
    subprocess.run(["secret-tool", "store", "--label=fambach YouTube token", *KEYRING],
                   input=creds.to_json(), text=True, check=True)


def load_credentials():
    raw = subprocess.run(["secret-tool", "lookup", *KEYRING], capture_output=True, text=True).stdout.strip()
    if not raw:
        sys.exit("no token in keyring, run: yt_upload.py auth -")
    creds = Credentials.from_authorized_user_info(json.loads(raw), SCOPES)
    if not creds.valid:
        creds.refresh(Request())
        store_token(creds)
    return creds


def auth(_):
    creds = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET, SCOPES).run_local_server(port=0)
    store_token(creds)
    print("token stored in keyring")


def check(_):
    youtube = build("youtube", "v3", credentials=load_credentials())
    channel = youtube.channels().list(part="snippet", mine=True).execute()["items"][0]
    print("ok", channel["id"], channel["snippet"]["title"])


def upload(video_dir):
    path = os.path.join(video_dir, "videos.csv")
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter=";"))
    youtube = build("youtube", "v3", credentials=load_credentials())
    for row in rows:
        if row.get("youtube_id"):
            continue
        body = {
            "snippet": {"title": row["titel"], "description": row["beschreibung"],
                        "tags": [t.strip() for t in row["tags"].split(",") if t.strip()], "categoryId": "28"},
            "status": {"privacyStatus": "private", "selfDeclaredMadeForKids": False},
        }
        request = youtube.videos().insert(part="snippet,status", body=body,
                                          media_body=MediaFileUpload(row["quelle"], chunksize=8 * 1024 * 1024, resumable=True))
        response = None
        while response is None:
            status, response = request.next_chunk()
            if status:
                print(f"{row['titel']}: {int(status.progress() * 100)} %")
        row["youtube_id"] = response["id"]
        with open(path + ".tmp", "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, FIELDS, delimiter=";", extrasaction="ignore")
            writer.writeheader()
            writer.writerows(rows)
        os.replace(path + ".tmp", path)
        print("uploaded", row["titel"], "https://youtu.be/" + response["id"])


if __name__ == "__main__":
    commands = {"auth": auth, "upload": upload, "check": check}
    if len(sys.argv) != 3 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](sys.argv[2])
