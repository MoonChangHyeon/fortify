# Fortify 확장자 분석 및 컴파일러 대상 식별 스크립트 (Batch)

## 개요

`analyze_extensions_default_compiler.bat`는 지정된 폴더 내 파일들의 확장자를 분석하고, Fortify SCA (Source Code Analyzer)의 설정 파일(`fortify-sca.properties`)을 참조하여 Fortify가 지원하는 확장자와 컴파일러가 대상으로 하는 확장자를 식별하여 요약 정보를 제공하는 Windows 배치 스크립트입니다.

## 1. 환경변수 수정방법

이 스크립트에서 가장 중요한 설정은 Fortify SCA의 속성 파일 경로입니다. 이 경로는 스크립트 내의 `FORTIFY_PROPERTIES_FILE` 변수에 저장됩니다.

스크립트를 올바르게 실행하려면, 이 변수의 값을 사용자 환경에 맞게 수정해야 합니다.

**수정 방법:**

1.  텍스트 편집기(예: 메모장, Notepad++)로 `analyze_extensions_default_compiler.bat` 파일을 엽니다.
2.  파일 상단 부근에서 다음 줄을 찾습니다:

    ```batch
    REM --- Configuration ---
    REM Fortify 설정 파일 경로 (사용자 환경에 맞게 수정 필요)
    set "FORTIFY_PROPERTIES_FILE=%USERPROFILE%\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"
    REM The above path was taken from the shell script. Adjust if your user profile path is different or the file is elsewhere.
    REM For example: set "FORTIFY_PROPERTIES_FILE=C:\Users\YourUser\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"
    ```
3.  위 `set "FORTIFY_PROPERTIES_FILE=..."` 줄의 경로를 실제 `fortify-sca.properties` 파일이 위치한 **절대 경로**로 변경합니다. 예를 들어, 파일이 `C:\Program Files\Fortify\SCA_and_Apps_24.4\Core\config\fortify-sca.properties`에 있다면 다음과 같이 수정합니다:

    ```batch
    set "FORTIFY_PROPERTIES_FILE=C:\Program Files\Fortify\SCA_and_Apps_24.4\Core\config\fortify-sca.properties"
    ```
4.  파일을 저장합니다.

## 2. 실행 방법

1.  **명령 프롬프트 또는 PowerShell 실행**:
    Windows에서 명령 프롬프트(cmd.exe) 또는 PowerShell을 실행합니다.

2.  **스크립트 실행**:
    다음 형식으로 스크립트를 실행합니다. `<대상_폴더_경로>` 부분에는 분석하고자 하는 소스 코드 폴더의 실제 경로를 입력합니다.
    ```batch
    analyze_extensions_default_compiler.bat "C:\경로\분석할\소스코드_폴더"
    ```
    또는 스크립트가 현재 디렉토리에 있다면:
    ```batch
    .\analyze_extensions_default_compiler.bat "C:\경로\분석할\소스코드_폴더"
    ```
    *   **주의**: 만약 폴더 경로에 공백이 포함되어 있다면, 반드시 전체 경로를 큰따옴표(`"`)로 감싸주어야 합니다.

**출력 예시:**

스크립트가 성공적으로 실행되면 다음과 유사한 형식으로 분석 결과가 터미널에 출력됩니다.
```
---------------------------------------------
 개수  | 전체 파일 확장자
---------------------------------------------
  150 | java
   80 | xml
   25 | js
   10 | (no extension)
---------------------------------------------
Fortify 지원 확장자:
---------------------------------------------
  150 | JAVA (java)
   80 | CONFIG (xml)
---------------------------------------------
Fortify 지원 확장자 총 개수: 230
---------------------------------------------
컴파일러 대상 확장자:
---------------------------------------------
  150 | JAVA (java)
---------------------------------------------
컴파일러 대상 확장자 총 개수: 150
---------------------------------------------
분석 완료.
---------------------------------------------
```


## 3. 에러 시 대처법

스크립트 실행 중 발생할 수 있는 일반적인 오류와 해결 방법은 다음과 같습니다.

*   **오류: 폴더 경로를 입력해주세요.**
    *   **원인**: 스크립트 실행 시 분석할 대상 폴더 경로를 인자로 전달하지 않았습니다.
    *   **대처법**: 스크립트 실행 명령어 뒤에 분석할 폴더의 경로를 정확히 입력합니다. (예: `analyze_extensions_default_compiler.bat "C:\my\project\src"`)

*   **오류: '<폴더_경로>'는 유효한 디렉토리가 아닙니다.**
    *   **원인**: 입력한 폴더 경로가 존재하지 않거나, 파일 경로이거나, 접근 권한이 없는 경우 발생합니다.
    *   **대처법**:
        *   입력한 폴더 경로가 정확한지, 오타가 없는지 확인합니다.
        *   해당 경로가 실제로 디렉터리인지 확인합니다 (명령 프롬프트에서 `dir "C:\입력한\폴더\경로"` 명령 사용).
        *   해당 디렉터리에 접근할 수 있는 권한이 있는지 확인합니다.

*   **오류: '<폴더_경로>' 디렉토리로 변경할 수 없습니다.**
    *   **원인**: 스크립트가 `pushd` 명령을 사용하여 해당 디렉터리로 이동하려고 했으나 실패했습니다. 이는 경로가 존재하지 않거나 접근 권한이 없을 때 발생할 수 있습니다.
    *   **대처법**: 위와 동일하게 폴더 경로의 유효성과 접근 권한을 확인합니다.

*   **경고: Fortify 설정 파일(...)을 찾을 수 없습니다. 파서 유형별 개수는 제공되지 않습니다.**
    *   **원인**: 스크립트 내에 설정된 `FORTIFY_PROPERTIES_FILE` 변수의 경로에 `fortify-sca.properties` 파일이 없거나, 해당 파일에 대한 읽기 권한이 없는 경우 발생합니다.
    *   **대처법**:
        1.  위 "1. 환경변수 수정방법" 섹션을 참고하여 `FORTIFY_PROPERTIES_FILE` 변수가 올바른 `fortify-sca.properties` 파일의 절대 경로를 가리키는지 다시 한번 확인하고 수정합니다.
        2.  해당 파일이 실제로 존재하는지, 그리고 현재 스크립트를 실행하는 사용자에게 읽기 권한이 있는지 확인합니다 (명령 프롬프트에서 `dir "C:\경로\to\fortify-sca.properties"` 명령 사용 및 파일 속성의 보안 탭 확인).

*   **임시 파일 생성 또는 접근 오류**
    *   **원인**: 스크립트는 `%TEMP%` 환경 변수에 지정된 경로(보통 `C:\Users\<사용자명>\AppData\Local\Temp`)에 임시 파일을 생성합니다. 이 디렉터리에 쓰기 권한이 없거나 디스크 공간이 부족할 때 문제가 발생할 수 있습니다.
    *   **대처법**:
        1.  `%TEMP%` 디렉터리에 현재 사용자가 쓰기 권한을 가지고 있는지 확인합니다.
        2.  시스템의 디스크 공간이 충분한지 확인합니다 (파일 탐색기에서 C: 드라이브 속성 확인 또는 `fsutil volume diskfree c:` 명령 사용).

*   **`findstr`, `sort` 등 명령어 실행 오류 (예: 'findstr'은(는) 내부 또는 외부 명령, 실행할 수 있는 프로그램, 또는 배치 파일이 아닙니다.)**
    *   **원인**: `findstr.exe`, `sort.exe`와 같은 표준 Windows 유틸리티가 시스템 경로 (`Path` 환경 변수)에 없거나 손상된 경우 발생할 수 있습니다. 이는 매우 드문 경우입니다.
    *   **대처법**:
        1.  `Path` 환경 변수에 `C:\Windows\System32` (또는 해당 OS의 시스템 디렉터리)가 포함되어 있는지 확인합니다.
        2.  Windows 시스템 파일 검사기 (`sfc /scannow`)를 실행하여 시스템 파일 손상을 복구해 볼 수 있습니다.

*   **분석 결과가 예상과 다르게 나올 경우**:
    *   **원인**:
        *   `FORTIFY_PROPERTIES_FILE`의 내용이 예상과 다를 수 있습니다 (예: `com.fortify.sca.fileextensions.`로 시작하는 항목의 누락 또는 오타).
        *   분석 대상 폴더 내 파일들의 확장자 구성이 예상과 다를 수 있습니다.
        *   스크립트 내부 로직이 특정 예외적인 파일명이나 확장자를 올바르게 처리하지 못했을 가능성이 있습니다.
    *   **대처법**:
        1.  `FORTIFY_PROPERTIES_FILE` 파일의 내용을 직접 열어 확장자와 파서 유형 매핑이 올바르게 정의되어 있는지 검토합니다.
        2.  분석 대상 폴더의 파일들을 직접 확인하여 실제 확장자 분포를 파악합니다.
        3.  필요하다면 스크립트의 각 처리 단계에 `echo` 문 등을 추가하여 중간 결과를 확인하며 디버깅해 볼 수 있습니다. (예: `echo DEBUG: Processing file %%F >> debug.log`)

오류 발생 시 터미널에 출력되는 메시지를 주의 깊게 읽어보면 문제 해결에 큰 도움이 됩니다.
