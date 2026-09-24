#!/usr/bin/env python3
"""Measure type-check time per function body with every declaration checked once.

The `-warn-long-*` warnings in a normal build (400 ms since 2026-09-21) are per batch job: each of
the ~47 frontend jobs lazily type-checks the declarations it references from
other files (property-wrapper macro expansions, memberwise inits, extensions)
and charges that to whichever body touched them first. A whole-module
`-typecheck` runs one job, so a body's number is its own cost. Only sites that
are slow *here* are worth rewriting; see Apple's "Improving build efficiency
with good coding practices" for the patterns (explicit types on complex
initial values, no long inferred closures or nested ternaries).

Usage:
    xcodebuild ... -derivedDataPath <dd> COMPILER_INDEX_STORE_ENABLE=NO build > build.log
    python3 Scripts/typecheck_timing.py build.log            # bodies over 100 ms
    python3 Scripts/typecheck_timing.py build.log --limit 50 # a lower bar
    python3 Scripts/typecheck_timing.py build.log --file Projects/StudentSelectionSheet.swift
                                                            # per-expression detail for one file

Reads the `builtin-SwiftDriver` line of the log, swaps `-c` for `-typecheck -wmo`
with the compiler's timing flags, runs it (~60 s) and prints the report.
"""
import collections
import os
import re
import shlex
import subprocess
import sys

DROP_FLAG = {
    '-c', '-incremental', '-save-temps', '-emit-dependencies', '-emit-module',
    '-serialize-diagnostics', '-emit-const-values', '-emit-objc-header',
    '-experimental-emit-module-separately', '-disable-cmo', '-enable-batch-mode',
    '-profile-coverage-mapping', '-profile-generate', '-emit-localized-strings',
    '-validate-clang-modules-once', '-no-color-diagnostics',
    # Compilation caching (Debug, since 2026-09-23): a cached job replays its outputs
    # instead of type-checking, so the timing flags would print nothing.
    '-cache-compile-job',
}
DROP_FLAG_WITH_VALUE = {
    '-emit-module-path', '-emit-objc-header-path', '-output-file-map',
    '-emit-localized-strings-path', '-const-gather-protocols-list',
    '-dependency-scan-serialize-diagnostics-path', '-clang-build-session-file',
    '-cas-path', '-scanner-prefix-map', '-scanner-prefix-map-sdk',
    '-scanner-prefix-map-toolchain', '-cache-replay-prefix-map',
}
TIMING = ['-typecheck', '-wmo',
          '-Xfrontend', '-debug-time-function-bodies',
          '-Xfrontend', '-debug-time-expression-type-checking']
BODY_KINDS = ('method', 'getter', 'setter', 'accessor', 'function', 'initializer',
              'subscript', 'deinit')


def driver_command(log_path):
    with open(log_path) as log:
        for line in log:
            if 'builtin-SwiftDriver -- ' in line:
                return shlex.split(line.split('builtin-SwiftDriver -- ', 1)[1])
    sys.exit("no builtin-SwiftDriver line in the log; run a full build first")


def typecheck_command(args):
    out, i = [], 0
    while i < len(args):
        arg = args[i]
        if arg in DROP_FLAG or arg.startswith('-j'):
            i += 1
        elif arg in DROP_FLAG_WITH_VALUE:
            i += 2
        elif arg == '-Xfrontend' and args[i + 1] == '-serialize-debugging-options':
            i += 2
        else:
            out.append(arg)
            i += 1
    return out + TIMING


def main():
    argv = sys.argv[1:]
    limit = float(argv[argv.index('--limit') + 1]) if '--limit' in argv else 100.0
    only_file = argv[argv.index('--file') + 1] if '--file' in argv else None
    log_path = [a for a in argv if a.endswith('.log')][0]

    cmd = typecheck_command(driver_command(log_path))
    cwd = cmd[cmd.index('-working-directory') + 1]
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)

    line_re = re.compile(r'^(?P<ms>[0-9.]+)ms\t(?P<path>[^:]+):(?P<line>\d+):(?P<col>\d+)\t?(?P<what>.*)$')
    bodies, expressions = [], collections.defaultdict(float)
    # The timers print on stderr alongside the diagnostics.
    for line in (result.stderr + result.stdout).splitlines():
        m = line_re.match(line)
        if not m:
            continue
        rel = os.path.relpath(m['path'], cwd)
        what = m['what'].split('@')[0].strip()
        if what and what.startswith(BODY_KINDS):
            bodies.append((float(m['ms']), rel, int(m['line']), what))
        elif not what:
            expressions[(rel, int(m['line']))] += float(m['ms'])

    if only_file:
        print(f"Expression time per line in {only_file} (>= 1 ms):")
        for (rel, line), ms in sorted(expressions.items(), key=lambda kv: kv[0][1]):
            if rel.endswith(only_file) and ms >= 1.0:
                print(f"{ms:8.1f} ms  line {line}")
        return

    slow = sorted((b for b in bodies if b[0] >= limit), reverse=True)
    total = sum(b[0] for b in bodies)
    print(f"{len(bodies)} bodies, {total / 1000:.1f} s of body type-checking in one job; "
          f"{len(slow)} over {limit:.0f} ms:")
    for ms, rel, line, what in slow:
        print(f"{ms:8.1f} ms  {rel}:{line}  {what}")
    other = [l for l in result.stderr.splitlines() if 'warning:' in l and 'to type-check' not in l]
    if other:
        print("\nOther warnings:")
        print('\n'.join(other))


if __name__ == '__main__':
    main()
