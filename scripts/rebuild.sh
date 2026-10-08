#!/bin/bash
# Build a pinned source tree using only the preceding generation's four tools.
set -euo pipefail
T=$(cd "$1" && pwd)
G=$(cd "$2" && pwd)
if [ -e "$3" ]; then echo "출력 경로가 이미 존재합니다: $3" >&2; exit 2; fi
mkdir -p "$3"
O=$(cd "$3" && pwd)
for a in 컴파일러 hmir을llvm으로 제품조정기 프로젝트조정기; do
  [ -x "$G/$a" ] || { echo "이전 세대 도구가 없습니다: $a" >&2; exit 2; }
done
artifacts=(컴파일러 hmir을llvm으로 제품조정기 프로젝트조정기)
if [ "$#" -eq 4 ]; then
  case "$4" in */*) echo '잘못된 도구 이름입니다' >&2; exit 2 ;; esac
  # Foundation Process may pass decomposed Hangul. Resolve it through the
  # filesystem and keep the canonical spelling for the project's artifact key.
  selected=
  for candidate in "${artifacts[@]}"; do
    if [ "$G/$4" -ef "$G/$candidate" ]; then selected=$candidate; break; fi
  done
  [ -n "$selected" ] || { echo "알 수 없는 도구 이름: $4" >&2; exit 2; }
  artifacts=("$selected")
fi
for a in "${artifacts[@]}"; do
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR="${TMPDIR:-/tmp}" \
    MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
    HMJE_MACOS_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
    HMJE_BOOTSTRAP_BIN="$G" HMJE_TOOL_BIN="$G" \
    HMJE_FRONTEND="$G/컴파일러" HMJE_BACKEND="$G/hmir을llvm으로" \
    HMJE_COORDINATOR="$G/제품조정기" HMJE_PROJECT_COORDINATOR="$G/프로젝트조정기" \
    HMJE_TOOLCHAIN_ROOT="$T" HMJE_COMPILER_ROOT="$T/compiler" \
    HMJE_HOST_SUPPORT="$T/compiler/runtime/host_support.c" \
    HMJE_CLANG=/usr/bin/clang HMJE_OBJECT_CACHE=off HMJE_KEEP_TEMP=1 \
    HMJE_CACHE_HOME="$O/cache" HMJE_PARSE_CACHE="$O/cache/parse" \
    HMJE_CACHE_ROOT="$O/cache/products" \
    "$T/bin/hmjec" --project "$T/compiler" --artifact "$a" \
      --target posix-host-exe --cache-dir "$O/cache/$a" --캐시끄기 -o "$O/$a" \
      > "$O/$a.log" 2>&1
  [ -x "$O/$a" ] || { echo "산출물이 없습니다: $a" >&2; exit 1; }
  echo "built $a"
done
