#!/bin/bash
# Operate only on fresh copies. The original distribution files remain read-only inputs.
set -euo pipefail
T=$(cd "$1" && pwd)
R=$(cd "$2" && pwd)
[ ! -e "$3" ] || { echo '출력 경로가 이미 존재합니다' >&2; exit 2; }
mkdir -p "$3"
O=$(cd "$3" && pwd)
/usr/bin/clang -O2 "$T/platforms/tools/targets/macho_uuid_normalize.c" -o "$O/normalize"
for a in 컴파일러 hmir을llvm으로 제품조정기 프로젝트조정기; do
    /usr/bin/codesign --verify --strict "$R/$a"
    cp "$R/$a" "$O/$a"
    /usr/bin/codesign --remove-signature "$O/$a"
    "$O/normalize" "$O/$a"
    /usr/bin/codesign --force --sign - --timestamp=none --identifier net.semtle.hmje.reproducible "$O/$a"
    "$O/normalize" --signature-padding "$O/$a"
done
