#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 2 ]] || {
  printf 'Usage: %s TEMPLATE OUTPUT [VARIABLE ...]\n' "$0" >&2
  exit 2
}

template_file=$1
output_file=$2
shift 2
output_mode=${OUTPUT_MODE:-0644}

python3 - "$template_file" "$output_file" "$output_mode" "$@" <<'PY'
import os
import pathlib
import re
import sys
import tempfile

template_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
output_mode = int(sys.argv[3], 8)
allowed_names = set(sys.argv[4:])
text = template_path.read_text(encoding="utf-8")
placeholders = set(re.findall(r"{{([A-Z][A-Z0-9_]*)}}", text))

unexpected = placeholders - allowed_names
if unexpected:
    raise SystemExit("template contains unapproved variables: " + ", ".join(sorted(unexpected)))

missing = [name for name in placeholders if not os.environ.get(name)]
if missing:
    raise SystemExit("required template variables are empty: " + ", ".join(sorted(missing)))

for name in placeholders:
    text = text.replace("{{" + name + "}}", os.environ[name])

if re.search(r"{{[A-Z][A-Z0-9_]*}}", text):
    raise SystemExit("rendered template still contains placeholders")

output_path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary_name = tempfile.mkstemp(prefix="." + output_path.name + ".", dir=output_path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(temporary_name, output_mode)
    os.replace(temporary_name, output_path)
except BaseException:
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
    raise
PY
