#!/bin/bash

# 스크립트 사용법: ./script_name.sh <대상_폴더_경로>

# 1. 입력값 (폴더 경로) 확인
if [ -z "$1" ]; then
  echo "오류: 폴더 경로를 입력해주세요."
  echo "사용법: $0 <폴더_경로>"
  exit 1
fi

TARGET_DIR="$1"

# 2. 입력된 경로가 실제 디렉토리인지 확인
if [ ! -d "$TARGET_DIR" ]; then
  echo "오류: '$TARGET_DIR'는 유효한 디렉토리가 아닙니다."
  exit 1
fi

# Fortify 설정 파일 경로 (사용자 환경에 맞게 수정 필요)
FORTIFY_PROPERTIES_FILE="/Users/munchanghyeon/Documents/Workspce/SCA/24.4/Core/config/fortify-sca.properties"

echo "선택된 폴더: $TARGET_DIR"

# 임시 파일 생성 및 정리 예약 (전체 확장자 목록용)
EXTENSIONS_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/ext_list.XXXXXX")
trap 'rm -f "$EXTENSIONS_TEMP_FILE"' EXIT INT TERM

# --- 데이터 저장을 위한 연관 배열 선언 ---
# Bash 4.0 이상에서 사용 가능
declare -A props_ext_to_parser       # properties 파일에서 읽은 '확장자 -> 파서' 매핑
declare -A hardcoded_ext_to_parser   # 하드코딩된 '확장자 -> 파서' 매핑
declare -A props_parser_counts       # properties 기반 파서별 파일 수
declare -A all_parser_counts         # 전체 파서(하드코딩 포함)별 파일 수
declare -A props_parser_to_exts      # properties 기반 '파서 -> 확장자 목록'
declare -A all_parser_to_exts        # 전체 '파서 -> 확장자 목록'

# 하드코딩 파서 설정
hardcoded_ext_to_parser[c]="C_LANG"
hardcoded_ext_to_parser[cpp]="CPP_LANG"

# --- fortify-sca.properties 파일에서 확장자-파서 매핑 정보 읽기 ---
if [ -f "$FORTIFY_PROPERTIES_FILE" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        if [[ "$key" == com.fortify.sca.fileextensions.* ]]; then
            # 키에서 'com.fortify.sca.fileextensions.' 부분을 제거하고 소문자로 변경
            ext_key=$(echo "${key#com.fortify.sca.fileextensions.}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
            parser_type=$(echo "$value" | tr -d '[:space:]')
            props_ext_to_parser["$ext_key"]="$parser_type"
        fi
    done < <(grep "^com\.fortify\.sca\.fileextensions\." "$FORTIFY_PROPERTIES_FILE")
else
    echo "경고: Fortify 설정 파일($FORTIFY_PROPERTIES_FILE)을 찾을 수 없습니다."
fi

# --- 대상 폴더의 파일들을 순회하며 데이터 집계 ---
while IFS= read -r -d $'\0' file_path; do
  filename=$(basename "$file_path")
  ext=""

  if [[ "$filename" == *.* ]]; then
    _ext_val="${filename##*.}"
    if [ -n "$_ext_val" ]; then
      ext=$(echo "$_ext_val" | tr '[:upper:]' '[:lower:]')
    fi
  fi
  
  # 전체 확장자 목록은 이전과 동일하게 임시 파일에 저장
  if [ -n "$ext" ]; then
    echo "$ext" >> "$EXTENSIONS_TEMP_FILE"
  else
    echo "(${filename##*.})" >> "$EXTENSIONS_TEMP_FILE"
  fi

  # 확장자가 없으면 파서 분석 건너뛰기
  if [ -z "$ext" ]; then
    continue
  fi

  # 파서 유형 결정
  parser_type=""
  # 1. 하드코딩된 파서 우선 확인
  if [[ -v "hardcoded_ext_to_parser[$ext]" ]]; then
    parser_type=${hardcoded_ext_to_parser[$ext]}
  # 2. properties 파일 기반 파서 확인
  elif [[ -v "props_ext_to_parser[$ext]" ]]; then
    parser_type=${props_ext_to_parser[$ext]}
  fi

  # properties 파일에 정의된 파서 정보 집계
  if [[ -v "props_ext_to_parser[$ext]" ]]; then
    prop_parser=${props_ext_to_parser[$ext]}
    ((props_parser_counts[$prop_parser]++))
    # 중복 확장자 방지를 위해 공백으로 구분된 문자열에 추가 후 나중에 처리
    if [[ ! "${props_parser_to_exts[$prop_parser]}" =~ (^|[[:space:]])"$ext"($|[[:space:]]) ]]; then
        props_parser_to_exts[$prop_parser]+="$ext "
    fi
  fi

  # 결정된 파서가 있으면 전체 파서 정보 집계
  if [ -n "$parser_type" ]; then
    ((all_parser_counts[$parser_type]++))
    if [[ ! "${all_parser_to_exts[$parser_type]}" =~ (^|[[:space:]])"$ext"($|[[:space:]]) ]]; then
        all_parser_to_exts[$parser_type]+="$ext "
    fi
  fi

done < <(find "$TARGET_DIR" -type f -print0)


# --- 결과 출력 ---

# 1. 전체 파일 확장자 목록 출력
echo "---------------------------------------------"
echo " 개수  | 전체 파일 확장자"
echo "---------------------------------------------"
if [ -s "$EXTENSIONS_TEMP_FILE" ]; then
  sort "$EXTENSIONS_TEMP_FILE" | uniq -c | awk '{printf "%5s | %s\n", $1, $2}' | sort -k1nr -k3
fi

# 결과 섹션을 출력하는 함수
# 인수: 1:섹션제목, 2:카운트배열이름, 3:확장자목록배열이름, 4:필터링할파서목록(선택)
print_section() {
    local title="$1"
    declare -n counts_ref="$2"   # 카운트 배열 참조
    declare -n exts_ref="$3"     # 확장자 목록 배열 참조
    local filter_arr=($4)        # 필터링할 파서 이름들
    
    local total_files=0
    local output=""
    
    # 카운트 기준으로 파서 이름 정렬
    for parser in "${!counts_ref[@]}"; do
        # 필터가 있으면, 필터 목록에 있는 파서만 처리
        if [ ${#filter_arr[@]} -gt 0 ]; then
            is_target=0
            for filter_item in "${filter_arr[@]}"; do
                if [[ "$parser" == "$filter_item" ]]; then
                    is_target=1
                    break
                fi
            done
            if [[ $is_target -eq 0 ]]; then
                continue
            fi
        fi

        count=${counts_ref[$parser]}
        total_files=$((total_files + count))
        
        # 확장자 목록을 ", "로 예쁘게 만들기
        ext_list=$(echo "${exts_ref[$parser]}" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        
        output+=$(printf "%5s | %s (%s)\n" "$count" "$parser" "$ext_list")
    done

    if [ -n "$output" ]; then
        echo "---------------------------------------------"
        echo "$title:"
        echo "---------------------------------------------"
        # 개수(내림차순) > 파서이름(오름차순) 순으로 정렬하여 출력
        echo -e "$output" | sort -k1nr -k3
        echo "---------------------------------------------"
        echo "$title 총 개수: $total_files"
    fi
}

# 2. "Fortify 지원 확장자" 섹션 출력
print_section "Fortify 지원 확장자" props_parser_counts props_parser_to_exts

# 3. "컴파일러 대상 확장자" 섹션 출력
COMPILER_ASSOCIATED_PARSER_TYPES=(
    "SCALA" "JAVA" "CSHARP" "VB" "SWIFT" "GO" "KOTLIN" "C_LANG" "CPP_LANG"
)
print_section "컴파일러 대상 확장자" all_parser_counts all_parser_to_exts "${COMPILER_ASSOCIATED_PARSER_TYPES[*]}"


echo "---------------------------------------------"
echo "분석 완료."