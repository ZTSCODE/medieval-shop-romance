"""Registers the opening film in data/content.json (opening.film) and its captions in localization/game.csv.

  python tools/content/build_opening_film.py [--edl outputs/opening-cg-film/edit/edl_v7.json]

The film itself is assets/video/opening/opening_film.ogv (no burned-in captions). Caption text and timing come from the
edit list the film was assembled from, so they always match its narration. Re-running is safe: only opening.film and the
OPENING_FILM_* rows are replaced; everything else in both files is kept as it is.
"""
import argparse
import csv
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
ap = argparse.ArgumentParser()
ap.add_argument("--edl", default="outputs/opening-cg-film/edit/edl_v7.json")
ap.add_argument("--video", default="res://assets/video/opening/opening_film.ogv")
ap.add_argument("--lead-in", type=float, default=0.0, help="seconds of black at the head of the .ogv (see docs/knowledge/opening-film-in-game.md)")
args = ap.parse_args()

with open(args.edl, encoding="utf-8") as f:
    edl = json.load(f)
captions = []
for item in sorted(edl["vo"], key=lambda i: i["at"]):
    for offset, length, en, zh in item["subs"]:
        captions.append([item["at"] + offset, item["at"] + offset + length, en, zh])
captions.sort(key=lambda c: c[0])
for current, following in zip(captions, captions[1:]):      # never two captions at once
    current[1] = min(current[1], following[0] - 0.04)

text = {"OPENING_FILM_SKIP": ("长按跳过", "Hold to skip")}
timed = []
for index, (start, end, en, zh) in enumerate(captions, 1):
    key = f"OPENING_FILM_LINE_{index:02d}"
    text[key] = (zh, en)
    timed.append({"start": round(start, 2), "end": round(end, 2), "key": key})

with open("data/content.json", encoding="utf-8") as f:
    content = json.load(f)
# The game's name rises over the last shot (the dark moor) and stays through the black that ends the film.
title = {"start": round(edl["marks"]["n20"], 2), "fade": 1.8, "key": "GAME_NAME"}
content["opening"]["film"] = {"video": args.video, "lead_in": args.lead_in, "skip_key": "OPENING_FILM_SKIP", "title": title, "captions": timed}
with open("data/content.json", "w", encoding="utf-8", newline="\n") as f:
    json.dump(content, f, ensure_ascii=False, indent=2)
    f.write("\n")

path = "localization/game.csv"
with open(path, encoding="utf-8", newline="") as f:
    raw = f.read()
eol = "\r\n" if "\r\n" in raw else "\n"
rows = [row for row in csv.reader(io.StringIO(raw)) if row and not row[0].startswith("OPENING_FILM_")]
buf = io.StringIO()
writer = csv.writer(buf, lineterminator=eol)
for row in rows:
    writer.writerow(row)
for key, (zh, en) in text.items():
    writer.writerow([key, zh, en])
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(buf.getvalue())
print(len(timed), "captions;", f"film length {edl['total']:.2f} s")
