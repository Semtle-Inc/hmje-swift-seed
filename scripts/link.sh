#!/bin/bash
# LLVM IR 하나를 posix-host-exe(macOS arm64)로 링크한다.
# 자립 컴파일러 제품조정기(조정기포직스링크)가 부르는 명령을 그대로 적은 것이다.
# 사람이 읽고 검토할 수 있도록 일부러 셸 명령으로만 쓴다(stage0 실행본을 거치지 않는다).
# 쓰임: link.sh <toolchain-root> <in.ll> <out.exe>
set -euo pipefail
T=$1; LL=$2; OUT=$3
CLANG=/usr/bin/clang
TG=$T/platforms/tools/targets
D=$(mktemp -d)
# Keep failed link intermediates for diagnosis; remove only known files on success.
F=(-target arm64-apple-darwin -O2)
$CLANG "${F[@]}" -ffunction-sections -fdata-sections -c "$LL" -o "$D/app.o"
$CLANG "${F[@]}" -DHMJE_POSIX_ENABLE_HOST_FILES=1 -c "$TG/posix_host_shim.c" -o "$D/shim.o"
$CLANG "${F[@]}" -c "$TG/async_host_runtime.c" -o "$D/async.o"
$CLANG "${F[@]}" -ffunction-sections -fdata-sections -I"$TG" -x c -c "$T/compiler/runtime/host_support.c" -o "$D/support.o"
$CLANG "${F[@]}" -fobjc-arc -x objective-c -c "$TG/posix_host_window.m" -o "$D/window.o"
$CLANG "${F[@]}" -fobjc-arc -x objective-c -c "$TG/posix_host_text_input.m" -o "$D/text-input.o"
$CLANG -target arm64-apple-darwin "$D/app.o" "$D/shim.o" "$D/async.o" "$D/support.o" "$D/window.o" "$D/text-input.o" \
  -pthread -Wl,-dead_strip -framework Cocoa -framework QuartzCore -framework Metal -framework ImageIO -framework UniformTypeIdentifiers \
  -o "$D/app"
# 재현 가능한 Mach-O: UUID 값을 0으로, 고정 식별자·타임스탬프 없는 ad-hoc 서명, 서명 여백 정규화.
$CLANG -O2 "$TG/macho_uuid_normalize.c" -o "$D/macho-uuid-normalize"
"$D/macho-uuid-normalize" "$D/app"
/usr/bin/codesign --force --sign - --timestamp=none --identifier net.semtle.hmje.reproducible "$D/app"
"$D/macho-uuid-normalize" --signature-padding "$D/app"
mv "$D/app" "$OUT"
for f in app.o shim.o async.o support.o window.o text-input.o macho-uuid-normalize; do unlink "$D/$f"; done
rmdir "$D"
