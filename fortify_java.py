import subprocess
import os
import shlex # 빌드 명령어 문자열을 안전하게 분리하기 위해 사용

# --- Configuration ---
# TODO: 사용자 환경에 맞게 이 섹션을 수정하세요.

# Fortify SCA bin 디렉토리 경로.
# 예: "/opt/Fortify/Fortify_SCA_and_Apps_23.2.0/bin"
# PATH에 sourceanalyzer가 이미 설정되어 있다면 None으로 두거나, 아래 FORTIFY_ANALYZER_EXECUTABLE에서 전체 경로를 지정하세요.
FORTIFY_BIN_DIR = None

# sourceanalyzer 실행 파일의 전체 경로 (옵션).
# FORTIFY_BIN_DIR이 None이고 PATH에 없다면 여기에 직접 지정하세요. 예: "/opt/Fortify/bin/sourceanalyzer"
# None으로 두면 "sourceanalyzer" 명령어를 PATH에서 찾습니다.
FORTIFY_ANALYZER_EXECUTABLE = None

# 분석할 Java 프로젝트의 루트 디렉토리 경로
PROJECT_DIR = "/path/to/your/java/project" # 예: "/home/user/my-java-app"

# Java 소스 코드 디렉토리 (PROJECT_DIR 기준 상대 경로)
# USE_BUILD_TOOL = False 일 경우에만 사용됩니다.
# 예: ["src/main/java", "another/source/folder"]
JAVA_SOURCE_DIRS = ["src/main/java"]
JAVA_VERSION = "11"  # 프로젝트에서 사용하는 JDK 버전 (예: "8", "11", "17")

# 빌드 도구 사용 여부 (Maven, Gradle 등)
# True로 설정하면 JAVA_SOURCE_DIRS 대신 BUILD_COMMAND가 번역 단계에서 사용됩니다.
USE_BUILD_TOOL = False

# 빌드 명령어 (USE_BUILD_TOOL이 True일 경우 사용)
# Fortify는 이 명령어를 감싸서 번역을 수행합니다.
# 예: "mvn clean package -DskipTests" 또는 "gradle clean build -x test"
BUILD_COMMAND = "mvn clean package -DskipTests"

# Fortify 스캔을 위한 고유 빌드 ID (프로젝트별로 구분되는 이름 권장)
BUILD_ID = "MyJavaProjectScan"

# 생성될 FPR 결과 파일 이름 (PROJECT_DIR 내에 생성됨)
OUTPUT_FPR_FILENAME = f"{BUILD_ID}.fpr"
# --- End of Configuration ---

def get_analyzer_path():
    """sourceanalyzer 실행 파일 경로를 결정합니다."""
    if FORTIFY_ANALYZER_EXECUTABLE:
        return FORTIFY_ANALYZER_EXECUTABLE
    if FORTIFY_BIN_DIR:
        return os.path.join(FORTIFY_BIN_DIR, "sourceanalyzer")
    return "sourceanalyzer" # PATH에서 찾도록 함

def run_fortify_command(args, working_dir):
    """
    Fortify SCA 명령어를 실행합니다.
    :param args: sourceanalyzer에 전달될 인자 리스트
    :param working_dir: 명령어가 실행될 작업 디렉토리
    :return: 성공 시 True, 실패 시 False
    """
    executable = get_analyzer_path()
    command = [executable] + args

    print(f"\n[INFO] Executing Fortify command in '{working_dir}':")
    # 명령어 출력 시 비밀번호 등이 포함되지 않도록 주의
    print(f"  {' '.join(command)}")

    try:
        # shell=False가 기본이며 보안상 권장됩니다. 명령어와 인자는 리스트로 전달합니다.
        # Fortify 출력은 UTF-8일 수 있으므로 encoding 명시
        result = subprocess.run(command, cwd=working_dir, check=True, capture_output=True, text=True, encoding='utf-8')
        print("[INFO] Command successful.")
        if result.stdout:
            # stdout이 매우 길 수 있으므로, 필요한 경우 일부만 출력하거나 파일로 저장하는 것을 고려
            print("[STDOUT]:\n" + result.stdout.strip()[:1000] + ("..." if len(result.stdout.strip()) > 1000 else ""))
        if result.stderr: # Fortify는 종종 stderr로 진행 상황이나 경고를 출력합니다.
            print("[STDERR]:\n" + result.stderr.strip()[:1000] + ("..." if len(result.stderr.strip()) > 1000 else ""))
        return True
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] Command failed with return code {e.returncode}: {' '.join(command)}")
        if e.stdout:
            print("[STDOUT_ERROR]:\n" + e.stdout.strip())
        if e.stderr:
            print("[STDERR_ERROR]:\n" + e.stderr.strip())
        return False
    except FileNotFoundError:
        print(f"[ERROR] Executable '{executable}' not found.")
        print("  Ensure Fortify SCA is installed and 'sourceanalyzer' is in your system PATH,")
        print("  or correctly set FORTIFY_ANALYZER_EXECUTABLE or FORTIFY_BIN_DIR in the script.")
        return False
    except Exception as e:
        print(f"[ERROR] An unexpected error occurred: {e}")
        return False

def main():
    print("Starting Fortify SCA Java analysis script...")

    # 프로젝트 디렉토리 존재 여부 확인
    if PROJECT_DIR == "/path/to/your/java/project" or not os.path.isdir(PROJECT_DIR):
        print(f"[CONFIG_ERROR] Project directory not found or not configured: {PROJECT_DIR}")
        print("  Please configure 'PROJECT_DIR' in the script with the correct path to your Java project.")
        return

    # 1. Clean: 이전 빌드/분석 결과 정리
    #    -b <BUILD_ID> -clean
    print("\n--- Step 1: Cleaning previous Fortify build ---")
    clean_args = ["-b", BUILD_ID, "-clean"]
    if not run_fortify_command(clean_args, PROJECT_DIR):
        print("[FAIL] Fortify clean step failed. Exiting.")
        return

    # 2. Translate: Java 코드 번역 (Fortify가 이해할 수 있는 형태로 변환)
    #    -b <BUILD_ID> [번역 옵션]
    print("\n--- Step 2: Translating Java code ---")
    translate_args = ["-b", BUILD_ID]

    if USE_BUILD_TOOL:
        if not BUILD_COMMAND:
            print("[CONFIG_ERROR] 'USE_BUILD_TOOL' is True, but 'BUILD_COMMAND' is not set.")
            return
        print(f"[INFO] Using build tool. Fortify will wrap the command: {BUILD_COMMAND}")
        # shlex.split은 공백을 기준으로 명령어를 안전하게 분리하여 리스트로 만듭니다.
        # Fortify는 빌드 명령어 앞에 다른 옵션 없이 바로 빌드 명령어를 받습니다.
        # 예: sourceanalyzer -b MyBuildID mvn clean package
        translate_args.extend(shlex.split(BUILD_COMMAND))
    else:
        if not JAVA_SOURCE_DIRS:
            print("[CONFIG_ERROR] 'USE_BUILD_TOOL' is False, but 'JAVA_SOURCE_DIRS' is empty.")
            return
        print(f"[INFO] Translating Java source files directly. JDK version for analysis: {JAVA_VERSION}")
        translate_args.extend(["-jdk", JAVA_VERSION])
        # PROJECT_DIR 기준으로 JAVA_SOURCE_DIRS에 지정된 소스 경로들을 추가
        # sourceanalyzer는 cwd (PROJECT_DIR) 기준으로 상대 경로를 해석합니다.
        for src_rel_path in JAVA_SOURCE_DIRS:
            translate_args.append(src_rel_path)
        print(f"[INFO] Source paths for translation (relative to project dir): {JAVA_SOURCE_DIRS}")

    if not run_fortify_command(translate_args, PROJECT_DIR):
        print("[FAIL] Fortify translate step failed. Exiting.")
        return

    # 3. Scan: 번역된 코드 분석 및 FPR 파일 생성
    #    -b <BUILD_ID> -scan -f <OUTPUT_FPR_FILENAME>
    print("\n--- Step 3: Scanning translated code ---")
    # FPR 파일은 PROJECT_DIR 내에 OUTPUT_FPR_FILENAME으로 저장됩니다.
    scan_args = ["-b", BUILD_ID, "-scan", "-f", OUTPUT_FPR_FILENAME]
    if not run_fortify_command(scan_args, PROJECT_DIR):
        print("[FAIL] Fortify scan step failed. Exiting.")
        return

    absolute_fpr_path = os.path.abspath(os.path.join(PROJECT_DIR, OUTPUT_FPR_FILENAME))
    print(f"\n[SUCCESS] Fortify SCA analysis complete!")
    print(f"  Build ID: {BUILD_ID}")
    print(f"  Results FPR file: {absolute_fpr_path}")
    print("  You can open this FPR file with Fortify Audit Workbench or upload it to Fortify Software Security Center (SSC).")

if __name__ == "__main__":
    # 스크립트 실행 전 기본적인 설정값 확인
    if PROJECT_DIR == "/path/to/your/java/project":
        print("[CONFIG_NOTICE] 'PROJECT_DIR' is set to its default example value.")
        print("  Please edit the script and set 'PROJECT_DIR' to your actual Java project path before running.")
    elif USE_BUILD_TOOL and BUILD_COMMAND == "mvn clean package -DskipTests" and not os.path.exists(os.path.join(PROJECT_DIR, "pom.xml")):
         print("[CONFIG_WARNING] 'USE_BUILD_TOOL' is True with the default Maven command,")
         print("  but 'pom.xml' was not found in PROJECT_DIR. Please verify your 'BUILD_COMMAND' and 'PROJECT_DIR'.")
    elif not USE_BUILD_TOOL and not JAVA_SOURCE_DIRS:
        print("[CONFIG_ERROR] 'USE_BUILD_TOOL' is False, but 'JAVA_SOURCE_DIRS' is empty.")
        print("  Please specify Java source directories for direct scanning.")
    else:
        main()