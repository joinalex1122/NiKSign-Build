"""Fail QA on actual compiler diagnostics; never suppress or filter out vendor warnings."""
import re
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(errors="replace")
diagnostics = [line for line in log.splitlines() if re.search(r"(?:^|\s)(?:warning|error):", line)]
if diagnostics:
    print("\n".join(diagnostics))
    raise SystemExit("QA failed: compiler diagnostics remain")
if "** BUILD SUCCEEDED **" not in log:
    raise SystemExit("QA failed: no successful build marker")
print("PASS: Xcode build succeeded with zero warning/error diagnostics")
