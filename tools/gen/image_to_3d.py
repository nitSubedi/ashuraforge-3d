"""Hunyuan3D image-to-3D via a HuggingFace Space (gradio_client).

Turns one T-pose character image into a textured mesh (.glb + .obj).

Usage:
  tools/gen/.venv/bin/python tools/gen/image_to_3d.py \
      assets/generation/references/hero_tpose.png assets/generation/out/hero

Env:
  HF_TOKEN   optional HuggingFace token (needed for ZeroGPU API quota on the
             official Space). Without it, falls back to the duplicate-friendly
             community Space if the official one rejects anonymous API calls.
  HF_SPACE   override the Space id (default: tencent/Hunyuan3D-2.1).
"""
import os
import shutil
import sys
from pathlib import Path

from gradio_client import Client, handle_file

DEFAULT_SPACE = os.environ.get("HF_SPACE", "tencent/Hunyuan3D-2.1")


def find_image_to_3d_endpoint(client: Client):
    """Pick the endpoint that takes an image and returns a mesh file.
    Prefer the full textured pipeline (generation_all); fall back to shape only.
    Returns the api_name string (with leading slash)."""
    api = client.view_api(return_format="dict")
    named = api.get("named_endpoints", {})
    # Prefer textured full pipeline.
    for key in named:
        if "generation_all" in key:
            return key
    for key in named:
        if "shape_generation" in key:
            return key
    raise RuntimeError(
        "No image-to-3D endpoint found. Endpoints: " + ", ".join(named.keys())
    )


def main(image_path: str, out_prefix: str):
    img = Path(image_path)
    if not img.exists():
        sys.exit(f"Input image not found: {img}")
    out = Path(out_prefix)
    out.parent.mkdir(parents=True, exist_ok=True)

    token = os.environ.get("HF_TOKEN")
    print(f"Connecting to Space {DEFAULT_SPACE} (token={'yes' if token else 'no'})...")
    client = Client(DEFAULT_SPACE, token=token)

    def call(api_name):
        return client.predict(
            caption=None,
            image=handle_file(str(img)),
            mv_image_front=None,
            mv_image_back=None,
            mv_image_left=None,
            mv_image_right=None,
            steps=50,
            guidance_scale=5.0,
            seed=1234,
            octree_resolution=320,
            check_box_rembg=True,
            num_chunks=8000,
            randomize_seed=False,
            api_name=api_name,
        )

    api = client.view_api(return_format="dict").get("named_endpoints", {})
    have = lambda n: any(n in k for k in api)
    # Prefer textured pipeline; fall back to shape-only if it errors server-side.
    result = None
    if have("generation_all"):
        try:
            print("Trying /generation_all (textured)...")
            result = call("/generation_all")
        except Exception as e:
            print(f"generation_all failed ({type(e).__name__}: {str(e)[:80]}); "
                  "falling back to /shape_generation (untextured).")
    if result is None and have("shape_generation"):
        print("Running /shape_generation (untextured)...")
        result = call("/shape_generation")
    if result is None:
        sys.exit("No usable image-to-3D endpoint on this Space.")

    def paths(res):
        items = res if isinstance(res, (list, tuple)) else [res]
        for it in items:
            p = it.get("value") if isinstance(it, dict) else it
            if isinstance(p, str) and p.lower().endswith((".glb", ".obj")):
                yield p

    saved = []
    for p in paths(result):
        dest = out.with_suffix(Path(p).suffix)
        shutil.copy(p, dest)
        saved.append(str(dest))
    if not saved:
        print("No mesh file in result; raw result:", result)
        sys.exit(1)
    print("Saved:", *saved, sep="\n  ")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: image_to_3d.py <input_image> <output_prefix>")
    main(sys.argv[1], sys.argv[2])
