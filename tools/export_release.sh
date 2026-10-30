#!/usr/bin/env bash
# Local exports pinned to official 4.7.2 release templates, no global engine install.
set -euo pipefail
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]]; then
  printf '%s\n' "Commit the candidate first: native release exports require a clean source tree." >&2
  exit 1
fi
SOURCE_COMMIT="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
SOURCE_TREE="$(git -C "$PROJECT_DIR" rev-parse 'HEAD^{tree}')"
TEMPLATES_DIR="${GODOT_TEMPLATES_DIR:-$PROJECT_DIR/../../work/runtime/export-templates}"
BUILD_PYTHON="${BUILD_PYTHON:-$PROJECT_DIR/work/pe-resources-venv/bin/python}"
if [[ ! -x "$BUILD_PYTHON" ]]; then
  printf '%s\n' "Create work/pe-resources-venv and install tools/build-requirements.txt, or set BUILD_PYTHON to that interpreter." >&2
  exit 1
fi
mkdir -p "$PROJECT_DIR/work/export-templates" "$PROJECT_DIR/builds/linux-release" "$PROJECT_DIR/builds/windows-release"
python3 - "$TEMPLATES_DIR" "$PROJECT_DIR/work/export-templates" <<'PY'
from pathlib import Path
import hashlib, shutil, sys
source, target = map(Path, sys.argv[1:])
expected = {
    'linux_release.x86_64': 'd9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63',
    'windows_release_x86_64.exe': 'd34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562',
}
for name, digest in expected.items():
    src = source / name
    if not src.is_file() or hashlib.sha256(src.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Official Godot 4.7.2 template missing or mismatched: {src}')
    dst = target / name
    if not dst.is_file() or hashlib.sha256(dst.read_bytes()).hexdigest() != digest:
        shutil.copy2(src, dst)
    dst.chmod(0o755)
    print('VERIFIED_TEMPLATE', name, digest)
PY
cd "$PROJECT_DIR"
./run.sh --headless --editor --import --quit
./run.sh --headless --export-release "Linux Release" "$PROJECT_DIR/builds/linux-release/outpost-exodus.x86_64"
./run.sh --headless --export-release "Windows Release" "$PROJECT_DIR/builds/windows-release/outpost-exodus.exe"
read -r APP_VERSION FILE_VERSION < <(python3 - <<'PY'
from pathlib import Path
import re
version = re.search(r'config/version="([^"]+)"', Path('project.godot').read_text()).group(1)
numbers = re.match(r'(\d+)\.(\d+)\.(\d+)', version).groups()
print(version, '.'.join(numbers) + '.0')
PY
)
"$BUILD_PYTHON" "$PROJECT_DIR/tools/patch_windows_resources.py" "$PROJECT_DIR/builds/windows-release/outpost-exodus.exe" --file-version "$FILE_VERSION" --product-version "$APP_VERSION" --report "$PROJECT_DIR/work/windows-pe-resources.json"
for platform in linux-release windows-release; do
  cp "$PROJECT_DIR/assets/fonts/NOTICE.txt" "$PROJECT_DIR/builds/$platform/FONT-NOTICE.txt"
  for notice in GODOT-LICENSE.txt GODOT-COPYRIGHT.txt; do
    cp "$PROJECT_DIR/licenses/$notice" "$PROJECT_DIR/builds/$platform/$notice"
  done
done
python3 - "$PROJECT_DIR" "$SOURCE_COMMIT" "$SOURCE_TREE" <<'PY'
from pathlib import Path
import hashlib, json, subprocess, sys
project = Path(sys.argv[1])
source_commit, source_tree = sys.argv[2:]
def git(*args):
    return subprocess.check_output(['git', '-C', str(project), *args], text=True).strip()
if git('status', '--porcelain') or git('rev-parse', 'HEAD') != source_commit or git('rev-parse', 'HEAD^{tree}') != source_tree:
    raise SystemExit('Source changed during export; discard these artifacts and export a clean candidate again.')
for platform, executable in [('linux', 'outpost-exodus.x86_64'), ('windows', 'outpost-exodus.exe')]:
    directory = project / 'builds' / (platform + '-release')
    data = {'source_commit': source_commit, 'source_tree': source_tree,
            'sha256': {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                       for name in [executable, 'outpost-exodus.pck']}}
    (directory / 'export-source.json').write_text(json.dumps(data, indent=2) + '\n')
PY
printf '%s\n' "Native exports finished. This does not constitute clean-machine or Steam acceptance."
