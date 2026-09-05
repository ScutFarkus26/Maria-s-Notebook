#!/usr/bin/env python3
"""Keep #Preview bodies out of the module-wide macro expansion.

A `#Preview { ... }` closure is a freestanding macro, so the compiler expands and
type-checks its body in every frontend job for the module, not just the file's
own. This script moves each body into a `private struct <File>Preview: View` in
the same file and leaves the macro body as the single call `<File>Preview()`,
which is type-checked once. `@Previewable @State` declarations become
`@State private var` on the generated struct. See CLAUDE.md, Build-setting rules.

Usage:
    python3 Scripts/hoist_previews.py "Maria's Notebook"          # dry run, lists files
    python3 Scripts/hoist_previews.py --apply "Maria's Notebook"  # rewrite in place

Idempotent: a preview whose body is already a single `<Name>Preview()` call is skipped.
"""
import glob
import os
import re
import sys

APPLY = "--apply" in sys.argv
ROOT = [a for a in sys.argv[1:] if not a.startswith("--")][0]

HEAD = re.compile(r'^(?P<indent>[ \t]*)#Preview(?P<args>\([^\n]*\))?\s*\{[ \t]*\n', re.M)
PREVIEWABLE = re.compile(r'^\s*@Previewable\s+(?P<decl>@State\s+(?:private\s+)?var\s+[^\n]+)$', re.M)
COMMENT = ("// The `#Preview` closure is expanded and type-checked in every compiler job\n"
           "// for the module; a private view is checked once, in this file's job.\n")


def find_close(source, i):
    """Index just past the brace that closes the one opened before `i`."""
    depth = 1
    while i < len(source) and depth:
        if source[i] == '{':
            depth += 1
        elif source[i] == '}':
            depth -= 1
        i += 1
    return i


def hoist(source, base):
    """Return (new_source, count) for one file."""
    out, pos, n = [], 0, 0
    for m in HEAD.finditer(source):
        if m.start() < pos:
            continue
        body_start = m.end()
        end = find_close(source, body_start)
        body = source[body_start:end - 1]
        if re.fullmatch(r'\s*\w+Preview\d*\(\)\s*', body):
            continue
        n += 1
        name = f"{base}Preview" + (str(n) if n > 1 else "")
        states = []
        body = PREVIEWABLE.sub(lambda mm: states.append(mm.group('decl').strip()) or '', body)
        lines = body.rstrip('\n').split('\n')
        while lines and not lines[0].strip():
            lines.pop(0)
        body_lines = [('    ' + line if line.strip() else '') for line in lines]
        state_lines = ''.join(
            f"    {d.replace('@State var', '@State private var')}\n" for d in states
        )
        struct = (
            (COMMENT if n == 1 else '')
            + f"private struct {name}: View {{\n"
            + state_lines + ('\n' if state_lines else '')
            + "    var body: some View {\n" + '\n'.join(body_lines) + "\n    }\n}\n\n"
        )
        args = m.group('args') or ''
        out.append(source[pos:m.start()])
        out.append(struct + f"#Preview{args} {{\n    {name}()\n}}")
        pos = end
    if not n:
        return source, 0
    out.append(source[pos:])
    return ''.join(out), n


changed_files = hoisted = 0
for path in sorted(glob.glob(os.path.join(ROOT, "**/*.swift"), recursive=True)):
    source = open(path).read()
    base = re.sub(r'[^A-Za-z0-9]', '', os.path.basename(path)[:-len('.swift')])
    new, n = hoist(source, base)
    if not n:
        continue
    changed_files += 1
    hoisted += n
    if APPLY:
        open(path, 'w').write(new)
    else:
        print(f"--- {path}: {n} preview(s)")
print(f"{'applied' if APPLY else 'dry run'}: {hoisted} previews in {changed_files} files")
