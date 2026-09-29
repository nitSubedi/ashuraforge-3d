# Mixamo-MCP Headless Auto-Rig Implementation Plan (Track 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a headless auto-rig capability to `v1xel/mixamo-mcp` so a freshly uploaded (un-rigged) character is rigged end-to-end without a human placing joint markers, then open a PR upstream from a fork.

**Architecture:** Mixamo's auto-rigger is a Bootstrap modal whose steps all advance via `.modal-footer button.btn-primary`. State is detected by CSS classes on the modal (`autorig-upload`, `autorig-overlay`, `autorig-uploading`, `autorig-holder`). We add (1) a pure decision function mapping a detected state to an action, and (2) a `complete_autorig` MCP tool that polls state and drives markers → processing → review → done. The state parser and decision logic are unit-tested against real HTML fixtures captured by a one-time spike; the live drive has an opt-in integration test.

**Tech Stack:** Python 3.12, Playwright (async in `mcp_server.py`, sync in `screens/`), BeautifulSoup4, FastMCP, pytest. Blender 4.x (headless) for one-time test-mesh conversion.

## Global Constraints

- Repo: `/Users/maauri/Projects/mixamo-mcp` (clone of `v1xel/mixamo-mcp`); upstream default branch `main`.
- No `CONTRIBUTING.md`, no `LICENSE`. Match existing README + commit style: capitalized, imperative subject (e.g. "Add upload auto-confirm, marker detection, list/select commands").
- ⚠️ License risk: repo ships no LICENSE — flag to maintainer in the PR; do not resolve silently.
- The MCP browser must be the **sole** owner of `browser_profile/`. Any standalone Playwright script (spike) requires the running MCP's Chromium to be stopped first (only one Chromium per `user_data_dir`).
- Mixamo accepts upload formats: `.fbx`, `.obj`, `.zip` only (NOT `.glb`).
- Use an **un-rigged** mesh to exercise the auto-rigger (OBJ strips the rig; a rigged FBX would skip markers).
- Python venv: `/Users/maauri/Projects/mixamo-mcp/.venv`. Run tests with `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest`.
- Preserve existing public tool names/behavior; this plan only *adds* `complete_autorig` and refines the `markers` state text.

---

## File Structure

- `screens/upload.py` (modify) — add `decide_autorig_action()` pure function; refine `markers` state text in `get_status()`.
- `mcp_server.py` (modify) — add `complete_autorig` tool; import the new helper.
- `tests/` (create) — pytest suite.
  - `tests/conftest.py` — fixture loader helper.
  - `tests/fixtures/autorig_*.html` — real captured modal HTML (from spike).
  - `tests/test_upload_status.py` — `get_status()` parser tests.
  - `tests/test_autorig_decision.py` — `decide_autorig_action()` tests.
  - `tests/test_complete_autorig.py` — driver test with a fake page (unit) + opt-in live test.
- `tools/glb_to_obj.py` (create) — Blender headless glb→obj converter (test-mesh prep).
- `tools/capture_autorig.py` (create) — one-time spike: upload + dump modal HTML to fixtures.
- `requirements-dev.txt` (create) — `pytest`.
- `README.md` (modify) — document `complete_autorig`.

---

## Task 1: Fork, feature branch, and pytest scaffold

**Files:**
- Create: `requirements-dev.txt`, `tests/__init__.py`, `tests/conftest.py`, `tests/test_smoke.py`

**Interfaces:**
- Produces: `tests/conftest.py` exposes `load_fixture(name: str) -> str` returning the text of `tests/fixtures/<name>`.

- [ ] **Step 1: Fork upstream and add a feature branch**

On GitHub, fork `v1xel/mixamo-mcp` into the user's account (user action — confirm done). Then:

```bash
cd /Users/maauri/Projects/mixamo-mcp
git remote add fork https://github.com/<your-username>/mixamo-mcp.git
git fetch origin
git checkout -b feat/headless-autorig origin/main
```

Expected: on branch `feat/headless-autorig`.

- [ ] **Step 2: Add dev requirements and install**

Create `requirements-dev.txt`:

```
pytest>=8.0
```

Run:

```bash
cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pip install -r requirements-dev.txt
```

Expected: pytest installs successfully.

- [ ] **Step 3: Add test package + fixture loader**

Create `tests/__init__.py` (empty). Create `tests/conftest.py`:

```python
from pathlib import Path

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def load_fixture(name: str) -> str:
    """Return the text contents of tests/fixtures/<name>."""
    return (FIXTURE_DIR / name).read_text(encoding="utf-8")
```

Create `tests/fixtures/.gitkeep` (empty) so the directory exists.

- [ ] **Step 4: Add a smoke test**

Create `tests/test_smoke.py`:

```python
def test_imports():
    import screens.upload  # noqa: F401
    assert hasattr(screens.upload, "get_status")
```

- [ ] **Step 5: Run the smoke test**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_smoke.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add requirements-dev.txt tests/
git commit -m "Add pytest scaffold for auto-rig work"
```

---

## Task 2: Prepare an un-rigged OBJ test mesh

**Files:**
- Create: `tools/glb_to_obj.py`
- Output (gitignored, not committed): `tools/test_assets/knight.obj`

**Interfaces:**
- Produces: a runnable Blender script invoked as
  `Blender --background --python tools/glb_to_obj.py -- <input.glb> <output.obj>`
  that exports all mesh geometry with no materials and no armature.

- [ ] **Step 1: Write the converter script**

Create `tools/glb_to_obj.py`:

```python
"""Headless Blender: convert a .glb to a geometry-only .obj (drops rig + materials).
Usage: blender --background --python tools/glb_to_obj.py -- input.glb output.obj
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
inp, outp = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=inp)
bpy.ops.wm.obj_export(
    filepath=outp,
    export_selected_objects=False,
    export_materials=False,
    export_triangulated_mesh=True,
)
print(f"WROTE {outp}")
```

- [ ] **Step 2: Run the conversion**

```bash
mkdir -p /Users/maauri/Projects/mixamo-mcp/tools/test_assets
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python /Users/maauri/Projects/mixamo-mcp/tools/glb_to_obj.py -- \
  /Users/maauri/Projects/ashuraforge-3d/assets/characters/Knight.glb \
  /Users/maauri/Projects/mixamo-mcp/tools/test_assets/knight.obj
```

Expected: console prints `WROTE .../knight.obj` and the file exists and is non-empty:

```bash
ls -la /Users/maauri/Projects/mixamo-mcp/tools/test_assets/knight.obj
```

- [ ] **Step 3: Gitignore the test asset output**

Append to `.gitignore`:

```
tools/test_assets/
```

- [ ] **Step 4: Commit**

```bash
git add tools/glb_to_obj.py .gitignore
git commit -m "Add Blender glb-to-obj test-mesh converter"
```

---

## Task 3: Spike — capture live auto-rigger modal HTML into fixtures

This task is investigative: run a one-time capture against live Mixamo to record the real modal HTML at each auto-rig state, saved as test fixtures for Tasks 4–5. It also validates that the advance button is `.modal-footer button.btn-primary` on the markers screen.

**Files:**
- Create: `tools/capture_autorig.py`
- Output (committed): `tests/fixtures/autorig_markers.html`, `autorig_processing.html`, `autorig_review.html`, `autorig_done.html`, and `tools/AUTORIG_NOTES.md`

**Interfaces:**
- Consumes: `tools/test_assets/knight.obj` (Task 2), a logged-in `browser_profile/`.
- Produces: HTML fixtures named exactly as above; `AUTORIG_NOTES.md` recording the footer-button selector(s), whether markers are pre-placed, and the state sequence observed.

- [ ] **Step 1: Ensure the MCP browser is stopped (sole-owner rule)**

The MCP server's headless Chromium must not be running, or the spike can't open the profile. Verify none is using the profile:

```bash
pgrep -f "user-data-dir=/Users/maauri/Projects/mixamo-mcp/browser_profile" || echo "clear"
```

Expected: `clear`. If not clear, stop the MCP's browser (in this Claude Code session, ask the user to disconnect the `mixamo` MCP via `/mcp`, or kill only MCP-owned chromium PIDs — never the user's login browser).

- [ ] **Step 2: Write the capture script**

Create `tools/capture_autorig.py`:

```python
"""One-time spike: upload an un-rigged OBJ and dump the auto-rigger modal HTML
at each state into tests/fixtures/. Requires a logged-in browser_profile and
NO other Chromium using that profile.

Usage: .venv/bin/python tools/capture_autorig.py tools/test_assets/knight.obj
"""
import asyncio
import sys
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
PROFILE_DIR = ROOT / "browser_profile"
FIXTURES = ROOT / "tests" / "fixtures"
MIXAMO_URL = "https://www.mixamo.com"


async def dump(page, name: str):
    FIXTURES.mkdir(parents=True, exist_ok=True)
    html = await page.content()
    (FIXTURES / f"autorig_{name}.html").write_text(html, encoding="utf-8")
    print(f"dumped autorig_{name}.html  ({len(html)} bytes)")


async def main(obj_path: str):
    async with async_playwright() as pw:
        ctx = await pw.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_DIR), headless=True,
            viewport={"width": 1280, "height": 900},
        )
        page = ctx.pages[0] if ctx.pages else await ctx.new_page()
        await page.goto(MIXAMO_URL)
        await page.wait_for_load_state("networkidle")

        await page.click('button:has-text("Upload Character")')
        await page.wait_for_selector('a:has-text("Select character file")', timeout=10_000)
        async with page.expect_file_chooser() as fc:
            await page.click('a:has-text("Select character file")')
        await (await fc.value).set_files(obj_path)

        # Capture each state as it appears. Poll up to ~3 min total.
        seen = set()
        for _ in range(180):
            html = await page.content()
            for cls, name in [
                ("autorig-overlay", "markers"),
                ("autorig-uploading", "processing"),
                ("autorig-holder", "review"),
            ]:
                if cls in html and name not in seen:
                    await dump(page, name)
                    seen.add(name)
                    # Record the modal-footer buttons present at this state.
                    btns = await page.eval_on_selector_all(
                        ".modal-footer button",
                        "els => els.map(e => ({cls:e.className, text:e.textContent.trim()}))",
                    )
                    print(f"[{name}] footer buttons: {btns}")
                    if name in ("markers", "review"):
                        await page.click(".modal-footer button.btn-primary")
                        await page.wait_for_timeout(1500)
            if "autorig-modal" not in html and seen:
                await dump(page, "done")
                seen.add("done")
                break
            await page.wait_for_timeout(1000)

        print("states captured:", sorted(seen))
        await ctx.close()


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
```

- [ ] **Step 3: Run the spike**

```bash
cd /Users/maauri/Projects/mixamo-mcp && \
  .venv/bin/python tools/capture_autorig.py tools/test_assets/knight.obj
```

Expected: prints the footer buttons per state and `states captured: ['done', 'markers', 'processing', 'review']` (order may vary). Fixture files exist in `tests/fixtures/`.

- [ ] **Step 4: Record findings**

Create `tools/AUTORIG_NOTES.md` documenting, from the spike output:
- The exact `.modal-footer` button classes/text at the markers screen and review screen.
- Whether `.btn-primary` is the advance button at the markers screen (expected) or a different selector.
- The observed state sequence (e.g. markers → processing → review → done).
- Any extra controls on the markers screen (skeleton LOD dropdown, symmetry checkbox).

If the advance button on the markers screen is NOT `.modal-footer button.btn-primary`, note the correct selector — Task 5's `_ADVANCE_SELECTOR` constant uses it.

- [ ] **Step 5: Commit fixtures + notes**

```bash
git add tests/fixtures/autorig_markers.html tests/fixtures/autorig_processing.html \
        tests/fixtures/autorig_review.html tests/fixtures/autorig_done.html \
        tools/capture_autorig.py tools/AUTORIG_NOTES.md
git commit -m "Add auto-rigger spike capture and DOM fixtures"
```

---

## Task 4: Parser support — refine `markers` state, test `get_status` against fixtures

**Files:**
- Modify: `screens/upload.py:27-28` (markers state text)
- Test: `tests/test_upload_status.py`

**Interfaces:**
- Consumes: fixtures from Task 3; `screens.upload.get_status(html: str) -> dict`.
- Produces: `get_status` returns `{"state": "markers", ...}` for the markers fixture, `{"state": "processing", ...}` for processing, `{"state": "review", ...}` for review, and `{}` (no autorig state) for done.

- [ ] **Step 1: Write failing tests against the captured fixtures**

Create `tests/test_upload_status.py`:

```python
from screens.upload import get_status
from tests.conftest import load_fixture


def test_markers_state():
    st = get_status(load_fixture("autorig_markers.html"))
    assert st["state"] == "markers"


def test_processing_state():
    st = get_status(load_fixture("autorig_processing.html"))
    assert st["state"] == "processing"
    assert isinstance(st["progress"], int)


def test_review_state():
    st = get_status(load_fixture("autorig_review.html"))
    assert st["state"] == "review"


def test_done_has_no_autorig_state():
    st = get_status(load_fixture("autorig_done.html"))
    assert st.get("state") not in ("markers", "processing", "review")
```

- [ ] **Step 2: Run tests to verify the markers test fails on the old text**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_upload_status.py -v`
Expected: `test_markers_state` PASSES if class detection already works, but the *message* still says "not supported". Confirm current text:

```bash
.venv/bin/python -c "from screens.upload import get_status; from tests.conftest import load_fixture; print(get_status(load_fixture('autorig_markers.html')))"
```

Expected: shows `text` containing "not supported" — the string we will change.

- [ ] **Step 3: Update the markers state text**

In `screens/upload.py`, replace lines 27–28:

```python
    if soup.find(class_="autorig-overlay"):
        return {"state": "markers", "text": "Marker placement required — not supported. Type 'close' to dismiss."}
```

with:

```python
    if soup.find(class_="autorig-overlay"):
        return {"state": "markers", "text": "Auto-rigger marker screen — use complete_autorig to accept and finish."}
```

- [ ] **Step 4: Add a test asserting the new message and run the suite**

Append to `tests/test_upload_status.py`:

```python
def test_markers_message_points_to_complete_autorig():
    st = get_status(load_fixture("autorig_markers.html"))
    assert "complete_autorig" in st["text"]
```

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_upload_status.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add screens/upload.py tests/test_upload_status.py
git commit -m "Refine auto-rigger markers state to point at complete_autorig"
```

---

## Task 5: Decision function + `complete_autorig` driver tool

**Files:**
- Modify: `screens/upload.py` (add `decide_autorig_action`; add `_ADVANCE_SELECTOR`)
- Modify: `mcp_server.py` (import helper; add `complete_autorig` tool)
- Test: `tests/test_autorig_decision.py`, `tests/test_complete_autorig.py`

**Interfaces:**
- Produces:
  - `screens.upload.decide_autorig_action(state: str) -> str` returning one of
    `"advance"` (markers, review), `"wait"` (processing), `"done"` (empty/animations),
    `"stop"` (error, change_character).
  - `screens.upload._ADVANCE_SELECTOR: str` — the marker/review advance button
    selector (default `".modal-footer button.btn-primary"`; override per Task 3 notes).
  - MCP tool `complete_autorig() -> str` that polls `get_status`, advances the
    modal until done or timeout, and returns a human-readable result.

- [ ] **Step 1: Write failing tests for the decision function**

Create `tests/test_autorig_decision.py`:

```python
from screens.upload import decide_autorig_action


def test_markers_advances():
    assert decide_autorig_action("markers") == "advance"


def test_review_advances():
    assert decide_autorig_action("review") == "advance"


def test_processing_waits():
    assert decide_autorig_action("processing") == "wait"


def test_empty_is_done():
    assert decide_autorig_action("") == "done"


def test_error_stops():
    assert decide_autorig_action("error") == "stop"


def test_change_character_stops():
    assert decide_autorig_action("change_character") == "stop"
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_autorig_decision.py -v`
Expected: FAIL with `ImportError: cannot import name 'decide_autorig_action'`.

- [ ] **Step 3: Implement the decision function and advance selector**

In `screens/upload.py`, add near the top after the existing module constants (after line 10):

```python
_ADVANCE_SELECTOR = ".modal-footer button.btn-primary"

_AUTORIG_ACTIONS = {
    "markers": "advance",
    "review": "advance",
    "processing": "wait",
    "error": "stop",
    "change_character": "stop",
}


def decide_autorig_action(state: str) -> str:
    """Map an auto-rigger state (from get_status) to a driver action.

    Returns one of: 'advance', 'wait', 'done', 'stop'.
    An empty/unknown state means the modal is gone -> 'done'.
    """
    if not state:
        return "done"
    return _AUTORIG_ACTIONS.get(state, "done")
```

- [ ] **Step 4: Run decision tests**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_autorig_decision.py -v`
Expected: all PASS.

- [ ] **Step 5: Write a failing test for the driver loop with a fake page**

Create `tests/test_complete_autorig.py`:

```python
import asyncio
from screens.upload import drive_autorig


class FakePage:
    """Serves a scripted sequence of HTML states; records advance clicks."""
    def __init__(self, html_sequence):
        self._seq = list(html_sequence)
        self.clicks = []

    async def content(self):
        # Return current state's html; hold on the last once exhausted.
        return self._seq[0] if len(self._seq) == 1 else self._seq.pop(0)

    async def click(self, selector):
        self.clicks.append(selector)

    async def wait_for_timeout(self, ms):
        await asyncio.sleep(0)


def _markers(): return '<div class="autorig-modal"><div class="autorig-overlay"></div><div class="modal-footer"><button class="btn btn-primary">Next</button></div></div>'
def _processing(): return '<div class="autorig-modal"><div class="autorig-uploading"><div class="progress-bar" aria-valuenow="50"></div></div></div>'
def _review(): return '<div class="autorig-modal"><div class="autorig-holder"><div class="autorig-info">Looks good</div></div><div class="modal-footer"><button class="btn btn-primary">Next</button></div></div>'
def _done(): return '<div id="site"></div>'


def test_drive_advances_through_states():
    page = FakePage([_markers(), _processing(), _review(), _done()])
    result = asyncio.run(drive_autorig(page, poll_ms=0, max_polls=50))
    assert result["state"] == "done"
    # advanced twice: once at markers, once at review
    assert page.clicks.count(".modal-footer button.btn-primary") == 2


def test_drive_stops_on_error():
    err = '<div class="autorig-modal">unable to map your existing skeleton</div>'
    page = FakePage([err])
    result = asyncio.run(drive_autorig(page, poll_ms=0, max_polls=5))
    assert result["state"] == "stopped"
    assert page.clicks == []
```

- [ ] **Step 6: Run to verify failure**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_complete_autorig.py -v`
Expected: FAIL with `ImportError: cannot import name 'drive_autorig'`.

- [ ] **Step 7: Implement `drive_autorig` (async, page-agnostic)**

In `screens/upload.py`, add at the end of the file:

```python
async def drive_autorig(page, poll_ms: int = 1000, max_polls: int = 180) -> dict:
    """Drive the auto-rigger modal to completion.

    Polls get_status, clicking the advance button on 'markers'/'review',
    waiting on 'processing', and finishing on 'done'. Returns a dict with
    'state' in {'done', 'stopped', 'timeout'} and a 'message'.
    """
    last_state = None
    for _ in range(max_polls):
        html = await page.content()
        state = get_status(html).get("state", "")
        last_state = state
        action = decide_autorig_action(state)
        if action == "done":
            return {"state": "done", "message": "Auto-rig complete."}
        if action == "stop":
            return {"state": "stopped", "message": f"Stopped at state '{state}'."}
        if action == "advance":
            await page.click(_ADVANCE_SELECTOR)
        await page.wait_for_timeout(poll_ms)
    return {"state": "timeout", "message": f"Timed out; last state '{last_state}'."}
```

- [ ] **Step 8: Run the driver tests**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest tests/test_complete_autorig.py -v`
Expected: both PASS.

- [ ] **Step 9: Add the `complete_autorig` MCP tool**

In `mcp_server.py`, update the import on line 31:

```python
from screens.upload import get_status as get_upload_status, drive_autorig
```

Then add a new tool after `confirm_review` (after line 287):

```python
@mcp.tool()
async def complete_autorig() -> str:
    """Drive the Auto-Rigger to completion headlessly: accept marker placement,
    wait for rigging, and confirm the review. Call after upload_character once
    status() reports the upload modal is open."""
    page = await _get_page()
    result = await drive_autorig(page)
    return result["message"]
```

- [ ] **Step 10: Verify the server imports cleanly**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -c "import mcp_server; print('ok')"`
Expected: prints `ok` (no import error).

- [ ] **Step 11: Commit**

```bash
git add screens/upload.py mcp_server.py tests/test_autorig_decision.py tests/test_complete_autorig.py
git commit -m "Add complete_autorig tool to drive headless auto-rigging"
```

---

## Task 6: Opt-in live integration test, README, and PR

**Files:**
- Test: `tests/test_live_autorig.py`
- Modify: `README.md`

**Interfaces:**
- Consumes: `drive_autorig`, a logged-in profile, `tools/test_assets/knight.obj`.

- [ ] **Step 1: Add an opt-in live integration test**

Create `tests/test_live_autorig.py`:

```python
"""Live end-to-end auto-rig test. Opt-in only (hits real Mixamo, needs login and
sole ownership of browser_profile). Run with: MIXAMO_LIVE=1 pytest tests/test_live_autorig.py
"""
import asyncio
import os
from pathlib import Path

import pytest
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
OBJ = ROOT / "tools" / "test_assets" / "knight.obj"

pytestmark = pytest.mark.skipif(
    os.environ.get("MIXAMO_LIVE") != "1", reason="set MIXAMO_LIVE=1 to run live test"
)


def test_live_autorig_completes():
    from screens.upload import drive_autorig

    async def run():
        async with async_playwright() as pw:
            ctx = await pw.chromium.launch_persistent_context(
                user_data_dir=str(ROOT / "browser_profile"), headless=True,
                viewport={"width": 1280, "height": 900},
            )
            page = ctx.pages[0] if ctx.pages else await ctx.new_page()
            await page.goto("https://www.mixamo.com")
            await page.wait_for_load_state("networkidle")
            await page.click('button:has-text("Upload Character")')
            await page.wait_for_selector('a:has-text("Select character file")', timeout=10_000)
            async with page.expect_file_chooser() as fc:
                await page.click('a:has-text("Select character file")')
            await (await fc.value).set_files(str(OBJ))
            result = await drive_autorig(page)
            await ctx.close()
            return result

    result = asyncio.run(run())
    assert result["state"] == "done", result
```

- [ ] **Step 2: Run the live test (requires MCP browser stopped + login)**

```bash
cd /Users/maauri/Projects/mixamo-mcp && MIXAMO_LIVE=1 .venv/bin/python -m pytest tests/test_live_autorig.py -v -s
```

Expected: PASS (`state == done`). If it times out at `markers`, re-check `_ADVANCE_SELECTOR` against `tools/AUTORIG_NOTES.md` and fix in `screens/upload.py`, then re-run.

- [ ] **Step 3: Confirm the default suite still skips the live test**

Run: `cd /Users/maauri/Projects/mixamo-mcp && .venv/bin/python -m pytest -v`
Expected: all unit tests PASS; `test_live_autorig` is SKIPPED.

- [ ] **Step 4: Document the tool in README**

In `README.md`, add `complete_autorig` to the tools list (match the existing format/wording). Include a one-line usage note: "After `upload_character`, call `complete_autorig` to finish rigging headlessly."

- [ ] **Step 5: Commit**

```bash
git add tests/test_live_autorig.py README.md
git commit -m "Add live auto-rig integration test and document complete_autorig"
```

- [ ] **Step 6: Push to fork and open the PR**

```bash
git push -u fork feat/headless-autorig
```

Open a PR from `<your-username>:feat/headless-autorig` into `v1xel/mixamo-mcp:main`. In the PR description:
- Summarize: headless auto-rig via `complete_autorig`; refined `markers` state.
- Note testing: unit tests over captured fixtures + opt-in live test.
- ⚠️ Raise the missing-LICENSE question with the maintainer.

---

## Self-Review

**Spec coverage (Track 1 portion of the design):**
- Headless auto-rig replacing the "markers not supported" dead-end → Tasks 4 & 5. ✓
- Spike to learn live DOM → Task 3. ✓
- Primary "accept auto-estimate" path → `decide_autorig_action` + `drive_autorig` advancing on markers. ✓
- Fallback coordinate-drag → intentionally deferred: only needed if Task 3 notes show markers are NOT pre-placed/accepted by clicking Next. If so, add a follow-up task; Task 3 Step 4 records this explicitly. (Documented gap, not silent.)
- Fork + feature branch PR workflow → Tasks 1 & 6. ✓
- Match repo conventions; flag missing LICENSE → Task 6 Step 6. ✓
- Sole-owner profile constraint → Task 3 Step 1, Task 6 Step 2. ✓

**Placeholder scan:** No TBD/TODO. The one deferred item (coordinate-drag fallback) is conditional on spike findings and explicitly recorded, not a vague placeholder.

**Type consistency:** `get_status(html)->dict` (existing) used consistently; `decide_autorig_action(state:str)->str` returns the same four literals used by `drive_autorig`; `drive_autorig(page, poll_ms, max_polls)->dict` with `state` key consumed by the `complete_autorig` tool and the live test; `_ADVANCE_SELECTOR` defined in Task 5 Step 3 and used in Step 7 and referenced in Task 6 Step 2.

**Note:** Tasks 4–6 depend on Task 3 fixtures existing. If the spike reveals a materially different markers screen (extra required dropdown, different advance selector), update `_ADVANCE_SELECTOR` and, if needed, add a marker-coordinate fallback task before Task 6.
