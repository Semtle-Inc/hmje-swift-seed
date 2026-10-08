#!/bin/bash
# 씨앗(Swift)으로 네 도구의 1세대를 만든다. stage0 실행본이나 그 산출물을 하나도 읽지 않는다.
#   1. plan        : Project.hmjep → 진입 파일·모듈 지도·모듈 집계 (정본 프로젝트조정기)
#   2. finishpoint : 소스 → LLVM IR (정본 컴파일러 + hmir을llvm으로)
#   3. link.sh     : LLVM IR → 실행본 (정본 제품조정기의 링크 명령)
# 프론트엔드 인자 모양은 정본 제품조정기가 프론트엔드를 부르는 모양과 같다.
# 쓰임: gen1.sh <toolchain-root> <out-dir>
set -euo pipefail
export PATH=/usr/bin:$PATH
SEED=$(cd "$(dirname "$0")/.." && pwd); T=$(cd "$1" && pwd); mkdir -p "$2"; O=$(cd "$2" && pwd)
case "$(uname -s)" in
  Darwin) PLATFORM=darwin; PROJECT_PLATFORM=macOS ;;
  *) echo "gen1.sh: darwin 외 호스트는 아직 검증하지 않았다" >&2; exit 2 ;;
esac
swift build -c release --package-path "$SEED" >/dev/null
B=$SEED/.build/release/hmje-seed
for a in 컴파일러 hmir을llvm으로 제품조정기 프로젝트조정기; do
  P=$O/plan/$a
  if [ -e "$P" ] || [ -e "$O/$a" ]; then echo "출력 경로가 이미 존재합니다: $P" >&2; exit 2; fi
  "$B" plan "$T/bin/hmjec-selfhost" "$T/compiler" "$a" posix-host-exe "$P" "$PROJECT_PLATFORM" --캐시끄기
  args=("$P/entry.hmje" "$T/library" "$PLATFORM" "$T/compiler/Sources/준비/기본동적배열.hmje" "$O/$a.hmir")
  while IFS= read -r l; do args+=("$l"); done < "$P/options"
  args+=(--module-map "$P/modules.tsv" --native-plan "$P/native.tsv")
  "$B" finishpoint "${args[@]}" --llvm "$O/$a.ll"
  "$SEED/scripts/link.sh" "$T" "$O/$a.ll" "$O/$a"
  echo "gen1 $a"
done
