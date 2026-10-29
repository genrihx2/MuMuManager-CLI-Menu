#!/usr/bin/env python3
from pathlib import Path

path = Path(r"C:\ggggggg\mumu-manager-cli\tests\test-changelog-sync.ps1")
text = path.read_text(encoding="utf-8")

if not text.endswith("\n"):
    text = text + "\n"
    path.write_text(text, encoding="utf-8")
    print("fixed trailing newline")
else:
    print("trailing newline already present")

if not text.rstrip().endswith("}\n"):
    text = text.rstrip("\n") + "\n}\n"
    path.write_text(text, encoding="utf-8")
    print("ensured file ends with }\n")
else:
    print("file already ends with }\n")

print("total lines:", text.count("\n"))
print("ends with }\n:", text.rstrip("\n").endswith("}") and text.endswith("\n"))
