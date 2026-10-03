#!/usr/bin/env python3
"""Generate art direction images through fal.ai's queue API (work item 0211).

    tools/art/generate.py --model flux2 --prompt "..." --out work/art/2026-10-03-furnace [--count 2] [--ratio 16:9] [--seed 7]

Models: flux2 (fal-ai/flux-2-pro, consistency and detail), banana (fal-ai/nano-banana-pro, world building).
The key comes from ~/.config/fal/key (one line) or $FAL_KEY and is never printed.
Every image lands in the output folder as <model>_<index>.<format> with the prompt in prompt.txt beside it.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

MODELS = {
    "flux2": "fal-ai/flux-2-pro",
    "banana": "fal-ai/nano-banana-pro",
}
FLUX_SIZES = {"16:9": (1536, 864), "4:3": (1280, 960), "1:1": (1024, 1024), "3:2": (1536, 1024), "21:9": (1792, 768)}


def read_key():
    key = os.environ.get("FAL_KEY", "").strip()
    path = os.path.expanduser("~/.config/fal/key")
    if not key and os.path.isfile(path):
        key = open(path).read().strip()
    if not key:
        sys.exit("no key: put it in ~/.config/fal/key or $FAL_KEY")
    return key


def request(url, key, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Key " + key, "Content-Type": "application/json"}
    call = urllib.request.Request(url, data=data, headers=headers, method=method or ("POST" if data else "GET"))
    try:
        with urllib.request.urlopen(call, timeout=120) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:600]
        sys.exit(f"{url}: HTTP {error.code}: {detail}")


def build_input(model, prompt, count, ratio, seed):
    if model == "flux2":
        width, height = FLUX_SIZES[ratio]
        body = {"prompt": prompt, "image_size": {"width": width, "height": height}, "num_images": count, "output_format": "png"}
    else:
        body = {"prompt": prompt, "aspect_ratio": ratio, "resolution": "2K", "num_images": count, "output_format": "png"}
    if seed is not None:
        body["seed"] = seed
    return body


def generate(model, prompt, count, ratio, seed, out):
    key = read_key()
    endpoint = MODELS[model]
    submitted = request(f"https://queue.fal.run/{endpoint}", key, build_input(model, prompt, count, ratio, seed))
    status_url, response_url = submitted["status_url"], submitted["response_url"]
    started = time.time()
    while True:
        status = request(status_url, key)
        if status.get("status") == "COMPLETED":
            break
        if time.time() - started > 600:
            sys.exit("timed out waiting for " + submitted.get("request_id", "?"))
        time.sleep(2)
    result = request(response_url, key)
    os.makedirs(out, exist_ok=True)
    existing = len([name for name in os.listdir(out) if name.startswith(model + "_")])
    written = []
    for index, image in enumerate(result.get("images", [])):
        extension = "png" if "png" in image.get("content_type", "png") else "jpg"
        path = os.path.join(out, f"{model}_{existing + index}.{extension}")
        with urllib.request.urlopen(image["url"], timeout=120) as source, open(path, "wb") as target:
            target.write(source.read())
        written.append(path)
    with open(os.path.join(out, "prompt.txt"), "a") as log:
        log.write(f"{model} seed={result.get('seed', seed)} ratio={ratio}\n{prompt}\n{' '.join(os.path.basename(p) for p in written)}\n\n")
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", choices=MODELS, default="flux2")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=2)
    parser.add_argument("--ratio", choices=FLUX_SIZES, default="16:9")
    parser.add_argument("--seed", type=int)
    arguments = parser.parse_args()
    for path in generate(arguments.model, arguments.prompt, arguments.count, arguments.ratio, arguments.seed, arguments.out):
        print(path)


if __name__ == "__main__":
    main()
