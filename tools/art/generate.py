#!/usr/bin/env python3
"""Generate art direction images for the booklet (work item 0211).

    tools/art/generate.py --model banana --prompt "..." --out work/art/2026-10-03-furnace [--count 1] [--ratio 16:9] [--seed 7] [--reference image.png ...]

Providers and keys, never printed:
  openrouter (default): ~/.config/openrouter/key or $OPENROUTER_API_KEY; POST https://openrouter.ai/api/v1/images,
      the cost of every call comes back in usage.cost and is logged.
  fal: ~/.config/fal/key or $FAL_KEY; the queue API at https://queue.fal.run.

Models (openrouter ids, fal ids): banana (google/gemini-3-pro-image, fal-ai/nano-banana-pro), banana2 (google/gemini-3.1-flash-image),
  gpt (openai/gpt-image-2.5-sunburst), seedream (bytedance-seed/seedream-4.5), flux2 (black-forest-labs/flux.2-pro, fal-ai/flux-2-pro).
Every image lands in the output folder as <model>_<index>.<format>; prompt.txt beside it records the model, the seed, the cost and the prompt.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

OPENROUTER_MODELS = {
    "banana": "google/gemini-3-pro-image",
    "banana2": "google/gemini-3.1-flash-image",
    "gpt": "openai/gpt-image-2.5-sunburst",
    "seedream": "bytedance-seed/seedream-4.5",
    "flux2": "black-forest-labs/flux.2-pro",
}
FAL_MODELS = {"banana": "fal-ai/nano-banana-pro", "flux2": "fal-ai/flux-2-pro"}
FLUX_SIZES = {"16:9": (1536, 864), "4:3": (1280, 960), "1:1": (1024, 1024), "3:2": (1536, 1024), "21:9": (1792, 768)}


def read_key(provider):
    variable, path = {"openrouter": ("OPENROUTER_API_KEY", "~/.config/openrouter/key"), "fal": ("FAL_KEY", "~/.config/fal/key")}[provider]
    key = os.environ.get(variable, "").strip()
    path = os.path.expanduser(path)
    if not key and os.path.isfile(path):
        key = open(path).read().strip()
    if not key:
        sys.exit(f"no {provider} key: put it in {path} or ${variable}")
    return key


def request(url, headers, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    call = urllib.request.Request(url, data=data, headers={**headers, "Content-Type": "application/json"}, method=method or ("POST" if data else "GET"))
    try:
        with urllib.request.urlopen(call, timeout=300) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        sys.exit(f"{url}: HTTP {error.code}: {error.read().decode(errors='replace')[:600]}")


REFERENCE_LONG_SIDE = 1024


def reference_data_uri(path):
    """The image as a JPEG data URI, the long side at most REFERENCE_LONG_SIDE:
    OpenRouter caps the request's text at 8 MB, which one 2K PNG exceeds."""
    from PIL import Image
    import io
    image = Image.open(path).convert("RGB")
    image.thumbnail((REFERENCE_LONG_SIDE, REFERENCE_LONG_SIDE), Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode()


def reference_entry(path):
    """One input_references element: the shape OpenRouter's images API takes."""
    return {"type": "image_url", "image_url": {"url": reference_data_uri(path)}}


def generate_openrouter(model, prompt, count, ratio, seed, references):
    headers = {"Authorization": "Bearer " + read_key("openrouter")}
    body = {"model": OPENROUTER_MODELS[model], "prompt": prompt, "n": count, "aspect_ratio": ratio, "resolution": "2K", "output_format": "png"}
    if seed is not None:
        body["seed"] = seed
    if references:
        body["input_references"] = [reference_entry(path) for path in references]
    result = request("https://openrouter.ai/api/v1/images", headers, body)
    images = [base64.b64decode(entry["b64_json"]) for entry in result.get("data", [])]
    cost = result.get("usage", {}).get("cost")
    return images, cost, seed


def generate_fal(model, prompt, count, ratio, seed, references):
    if references:
        sys.exit("references are an openrouter feature in this script")
    headers = {"Authorization": "Key " + read_key("fal")}
    endpoint = FAL_MODELS[model]
    if model == "flux2":
        width, height = FLUX_SIZES[ratio]
        body = {"prompt": prompt, "image_size": {"width": width, "height": height}, "num_images": count, "output_format": "png"}
    else:
        body = {"prompt": prompt, "aspect_ratio": ratio, "resolution": "2K", "num_images": count, "output_format": "png"}
    if seed is not None:
        body["seed"] = seed
    submitted = request(f"https://queue.fal.run/{endpoint}", headers, body)
    started = time.time()
    while request(submitted["status_url"], headers).get("status") != "COMPLETED":
        if time.time() - started > 600:
            sys.exit("timed out waiting for " + submitted.get("request_id", "?"))
        time.sleep(2)
    result = request(submitted["response_url"], headers)
    images = []
    for image in result.get("images", []):
        with urllib.request.urlopen(image["url"], timeout=120) as source:
            images.append(source.read())
    return images, None, result.get("seed", seed)


def write_images(out, model, prompt, ratio, images, cost, seed):
    os.makedirs(out, exist_ok=True)
    existing = len([name for name in os.listdir(out) if name.startswith(model + "_")])
    written = []
    for index, data in enumerate(images):
        path = os.path.join(out, f"{model}_{existing + index}.png")
        with open(path, "wb") as target:
            target.write(data)
        written.append(path)
    cost_text = f"${cost:.3f}" if isinstance(cost, (int, float)) else "cost unknown"
    with open(os.path.join(out, "prompt.txt"), "a") as log:
        log.write(f"{model} seed={seed} ratio={ratio} {cost_text}\n{prompt}\n{' '.join(os.path.basename(p) for p in written)}\n\n")
    return written, cost_text


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--provider", choices=["openrouter", "fal"], default="openrouter")
    parser.add_argument("--model", choices=OPENROUTER_MODELS, default="banana")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--count", type=int, default=1, help="images per call; the Google models accept only 1")
    parser.add_argument("--ratio", choices=FLUX_SIZES, default="16:9")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--reference", action="append", default=[], help="a reference image (openrouter), repeatable; sent as a JPEG of at most 1024 px")
    arguments = parser.parse_args()
    if arguments.provider == "fal" and arguments.model not in FAL_MODELS:
        sys.exit(f"fal in this script offers {', '.join(FAL_MODELS)}")
    generate = generate_openrouter if arguments.provider == "openrouter" else generate_fal
    images, cost, seed = generate(arguments.model, arguments.prompt, arguments.count, arguments.ratio, arguments.seed, arguments.reference)
    if not images:
        sys.exit("the model returned no image")
    written, cost_text = write_images(arguments.out, arguments.model, arguments.prompt, arguments.ratio, images, cost, seed)
    print(cost_text)
    for path in written:
        print(path)


if __name__ == "__main__":
    main()
