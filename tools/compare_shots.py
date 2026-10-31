"""Pixel-diff two screenshot sets (renderer A/B, title reference vs rebuild).

    python tools/compare_shots.py --a old_dir --b new_dir --out report.json
    python tools/compare_shots.py --a old.png --b new.png
    python tools/compare_shots.py --a old_dir --b new_dir --contact diff_contact.png

Every file in --a is looked up by name in --b and diffed. Exit code 1 when any
pair is missing, has a different size, or exceeds the thresholds; the JSON report
always lists every pair so a reviewer can see what changed and by how much.

Thresholds (255-scale):
  --mean-threshold        2.0   mean absolute difference over all pixels/channels
  --structural-threshold  1.0   percent of pixels whose worst channel differs > 24

Read-only on the project; images may come from any directory (e.g. a Godot
capture folder under the repo's screenshots/ tree).
"""
import argparse
import json
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - Pillow is part of the dev environment
    print("Pillow is required: python -m pip install pillow", file=sys.stderr)
    raise SystemExit(2)

try:
    import numpy as np
except ImportError:  # optional speed-up; PIL fallback below
    np = None


IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}


def _images(path):
    if os.path.isdir(path):
        names = sorted(
            name for name in os.listdir(path)
            if os.path.splitext(name)[1].lower() in IMAGE_EXT
        )
        return [(name, os.path.join(path, name)) for name in names]
    return [(os.path.basename(path), path)]


def _rgb(path):
    with Image.open(path) as img:
        return img.convert("RGB")


def _stats(a, b):
    """Return (mean_abs, p99_abs, pct_gt8, pct_gt24, max_abs)."""
    if np is not None:
        left = np.asarray(a, dtype=np.int16)
        right = np.asarray(b, dtype=np.int16)
        diff = np.abs(left - right)
        mean_abs = float(diff.mean())
        worst = diff.max(axis=2)
        p99 = float(np.percentile(worst, 99))
        total = float(worst.size)
        pct_gt8 = float((worst > 8).sum()) / total * 100.0
        pct_gt24 = float((worst > 24).sum()) / total * 100.0
        return mean_abs, p99, pct_gt8, pct_gt24, int(worst.max())
    # PIL fallback: per-channel mean + a coarse structural proxy via histogram.
    from PIL import ImageChops, ImageStat
    diff = ImageChops.difference(a, b)
    mean = sum(ImageStat.Stat(diff).mean) / 3.0
    hist = diff.convert("L").histogram()
    total = float(sum(hist)) or 1.0
    heavy = sum(hist[25:]) / total * 100.0
    mid = sum(hist[9:]) / total * 100.0
    return mean, float(max(i for i, c in enumerate(hist) if c)), mid, heavy, 255


def _compare_pair(name, path_a, path_b, mean_threshold, structural_threshold):
    row = {"name": name, "a": path_a, "b": path_b}
    if not os.path.isfile(path_a):
        row.update({"status": "missing_a"})
        return row
    if not os.path.isfile(path_b):
        row.update({"status": "missing_b"})
        return row
    img_a = _rgb(path_a)
    img_b = _rgb(path_b)
    row["size_a"] = list(img_a.size)
    row["size_b"] = list(img_b.size)
    if img_a.size != img_b.size:
        row.update({"status": "size_mismatch"})
        return row
    mean_abs, p99, pct_gt8, pct_gt24, max_abs = _stats(img_a, img_b)
    row.update({
        "status": "ok",
        "mean_abs": round(mean_abs, 4),
        "p99_abs": round(p99, 3),
        "pct_gt8": round(pct_gt8, 4),
        "pct_gt24": round(pct_gt24, 4),
        "max_abs": max_abs,
    })
    row["pass"] = mean_abs <= mean_threshold and pct_gt24 <= structural_threshold
    return row


def _contact_sheet(rows, path):
    """Side-by-side |diff| sheet so a human can see where the change is."""
    if np is None:
        print("contact sheet needs numpy", file=sys.stderr)
        return
    from PIL import ImageChops
    panels = []
    for row in rows:
        if row.get("status") != "ok":
            continue
        img_a = _rgb(row["a"])
        img_b = _rgb(row["b"])
        diff = ImageChops.difference(img_a, img_b)
        panels.append((img_a, img_b, diff))
    if not panels:
        return
    width = panels[0][0].size[0]
    height = panels[0][0].size[1]
    gap = 4
    sheet = Image.new("RGB", (width * 3 + gap * 2, height * len(panels)), (20, 20, 24))
    for index, (img_a, img_b, diff) in enumerate(panels):
        y = index * height
        sheet.paste(img_a, (0, y))
        sheet.paste(img_b, (width + gap, y))
        sheet.paste(diff, (width * 2 + gap * 2, y))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)
    print("contact sheet: %s" % path)


def main(argv):
    parser = argparse.ArgumentParser(description="Pixel-diff two screenshot sets.")
    parser.add_argument("--a", required=True, help="reference image or directory")
    parser.add_argument("--b", required=True, help="candidate image or directory")
    parser.add_argument("--out", default="", help="JSON report path (optional)")
    parser.add_argument("--mean-threshold", type=float, default=2.0)
    parser.add_argument("--structural-threshold", type=float, default=1.0,
                        help="percent of pixels with a channel diff > 24")
    parser.add_argument("--contact", default="", help="optional side-by-side diff sheet")
    parser.add_argument("--allow-missing", action="store_true",
                        help="missing files are warnings instead of failures")
    args = parser.parse_args(argv)

    for label, path in (("a", args.a), ("b", args.b)):
        if not os.path.exists(path):
            print("--%s does not exist: %s" % (label, path), file=sys.stderr)
            return 2

    rows = [
        _compare_pair(name, path_a, os.path.join(args.b, name) if os.path.isdir(args.b) else args.b,
                      args.mean_threshold, args.structural_threshold)
        for name, path_a in _images(args.a)
    ]
    failed = [row for row in rows if row.get("status") != "ok" or not row.get("pass")]
    if args.allow_missing:
        failed = [row for row in failed if row.get("status") not in ("missing_a", "missing_b")]

    print("%-46s %9s %9s %8s %8s %s" % ("file", "mean", "p99", "%>8", "%>24", "verdict"))
    for row in rows:
        if row.get("status") == "ok":
            print("%-46s %9.3f %9.2f %7.2f%% %7.2f%% %s" % (
                row["name"][:46], row["mean_abs"], row["p99_abs"],
                row["pct_gt8"], row["pct_gt24"], "PASS" if row["pass"] else "FAIL"))
        else:
            print("%-46s %s" % (row["name"][:46], row["status"].upper()))
    if args.contact:
        _contact_sheet(rows, args.contact)

    report = {
        "a": os.path.abspath(args.a),
        "b": os.path.abspath(args.b),
        "pairs": rows,
        "failed": len(failed),
        "total": len(rows),
        "mean_threshold": args.mean_threshold,
        "structural_threshold": args.structural_threshold,
        "passed": not failed,
    }
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, ensure_ascii=False)
        print("report: %s" % args.out)
    print("%d/%d pairs within threshold" % (len(rows) - len(failed), len(rows)))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
