# Fortify 확장자 분석 및 컴파일러 대상 식별 (Windows Batch)

## 개요

`analyze_extensions_default_compiler.bat`는 지정된 폴더 내 파일들의 확장자를 분석하고, Fortify SCA (Source Code Analyzer)의 설정 파일(`fortify-sca.properties`)을 참조하여 Fortify가 지원하는 확장자와 컴파일러가 대상으로 하는 확장자를 식별하여 요약 정보를 제공하는 Windows 배치 스크립트입니다.

이 스크립트는 원래 `analyze_extensions_default_compiler.sh` (Bash 셸 스크립트)의 기능을 Windows 환경에서 유사하게 구현한 것입니다.

## 주요 기능

*   **전체 파일 확장자 분석**: 대상 폴더 내 모든 파일의 확장자를 수집하고, 각 확장자별 파일 개수를 집계하여 보여줍니다.
*   **Fortify 지원 확장자 식별**: `fortify-sca.properties` 파일에 정의된 확장자-파서 매핑 정보를 기반으로, 대상 폴더 내에서 발견된 Fortify 지원 확장자 및 관련 파서 유형, 그리고 각 파서 유형별 파일 개수를 보여줍니다.
*   **컴파일러 대상 확장자 식별**: 스크립트 내에 미리 정의된 컴파일러 관련 파서 유형(예: JAVA, CSHARP, C_LANG, CPP_LANG 등)과 연관된 확장자들을 식별하고, 각 파서 유형별 파일 개수를 보여줍니다.
*   **하드코딩된 확장자 처리**: C (`.c` -> `C_LANG`) 및 C++ (`.cpp` -> `CPP_LANG`) 확장자는 `fortify-sca.properties` 파일에 정의되어 있지 않더라도 기본적으로 인식합니다.
*   **대소문자 구분 없음**: 확장자 비교 시 대소문자를 구분하지 않습니다 (모두 소문자로 변환하여 처리).

## 사전 준비 사항

1.  **Windows 환경**: 이 스크립트는 Windows 명령 프롬프트(cmd.exe) 환경에서 실행됩니다.
2.  **Fortify SCA 설정 파일**: `fortify-sca.properties` 파일의 정확한 경로가 필요합니다. 스크립트 내에서 이 파일의 경로를 설정해야 합니다.

## 설정

스크립트를 실행하기 전에, 스크립트 파일 상단의 `FORTIFY_PROPERTIES_FILE` 변수 값을 실제 `fortify-sca.properties` 파일이 위치한 경로로 수정해야 합니다.

```batch
REM --- Configuration ---
REM Fortify 설정 파일 경로 (사용자 환경에 맞게 수정 필요)
set "FORTIFY_PROPERTIES_FILE=%USERPROFILE%\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"
REM 예시: set "FORTIFY_PROPERTIES_FILE=C:\Program Files\Fortify\Fortify_SCA_and_Apps_24.4\Core\config\fortify-sca.properties"
