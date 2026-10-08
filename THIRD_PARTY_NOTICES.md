# 제삼자 고지

이 저장소의 HMJE 라이선스와 별도로, 포함된 제삼자 소스에는 원래 제공 조건이 적용됩니다.

## 포함된 자료

`reference/`의 부트스트랩 소스 아카이브에는 SQLite 소스가 포함됩니다. 아카이브 내부의 경로와 고지는 압축을 해제한 뒤 확인할 수 있습니다.

| 자료 | 아카이브 내부 위치 | 제공 조건 |
| --- | --- | --- |
| SQLite | `library/Native/SQLite/vendor/sqlite3.c`, `sqlite3.h` | 퍼블릭 도메인; 각 원본 파일의 고지 보존 |

Beta 1 아카이브의 SQLite 버전은 3.53.4이며, 출처는 `library/Native/SQLite/PROVENANCE.md`에 기록되어 있습니다. SQLite의 제공 조건은 [공식 고지](https://www.sqlite.org/copyright.html)를 참조하십시오.

폰트, HmjeUI 자산 및 외부 모델 파일은 이 저장소에 포함되지 않습니다. 루트의 [Unicode License v3](UNICODE-LICENSE.txt)는 원본 소스 저장소에서 보존한 고지 사본이며, HmjeUI의 Unicode 데이터나 폰트 자산을 포함한다는 의미는 아닙니다.

## 외부 빌드 도구

Swift, LLVM/Clang, 운영체제 SDK 및 시스템 라이브러리는 외부 빌드 의존성이며 이 저장소에 포함되지 않습니다. 각 제공자의 라이선스와 사용 조건이 적용됩니다. LLVM을 별도로 배포하는 경우 [LLVM 라이선스](https://llvm.org/LICENSE.txt)를 확인하십시오.
