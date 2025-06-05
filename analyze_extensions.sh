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
FORTIFY_PROPERTIES_FILE="/Users/munchanghyeon/Documents/Workspce/SCA/24.4/Core/config/fortify-sca.properties" # 제공된 경로 사용

echo "선택된 폴더: $TARGET_DIR"

# 임시 파일들 생성 및 정리 예약
EXTENSIONS_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/ext_list.XXXXXX")
PARSER_TYPE_COUNT_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/parser_type_counts.XXXXXX") # 모든 파서 유형 카운트 (하드코딩 포함)
FOUND_PARSER_EXT_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/found_parser_ext.XXXXXX")    # 모든 파서:확장자 매핑 (하드코딩 포함)
PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/prop_parser_counts.XXXXXX") # Properties 기반 파서 카운트
PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/prop_found_ext.XXXXXX")    # Properties 기반 파서:확장자 매핑
trap 'rm -f "$EXTENSIONS_TEMP_FILE" "$PARSER_TYPE_COUNT_TEMP_FILE" "$FOUND_PARSER_EXT_TEMP_FILE" "$PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE" "$PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE"' EXIT INT TERM

echo "---------------------------------------------"
echo " 개수  | 전체 파일 확장자"
echo "---------------------------------------------"

# fortify-sca.properties 파일에서 확장자-파서유형 매핑 정보 읽기
ext_keys=()
parser_values=()
if [ -f "$FORTIFY_PROPERTIES_FILE" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        if [[ "$key" == com.fortify.sca.fileextensions.* ]]; then
            ext_key=$(echo "${key#com.fortify.sca.fileextensions.}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
            parser_type=$(echo "$value" | tr -d '[:space:]')
            ext_keys+=("$ext_key")
            parser_values+=("$parser_type")
        fi
    done < <(grep "^com\.fortify\.sca\.fileextensions\." "$FORTIFY_PROPERTIES_FILE")
else
    echo "경고: Fortify 설정 파일($FORTIFY_PROPERTIES_FILE)을 찾을 수 없습니다. 파서 유형별 개수는 제공되지 않습니다."
fi

find "$TARGET_DIR" -type f -print0 | while IFS= read -r -d $'\0' file_path; do
  filename=$(basename "$file_path")
  current_file_extension_for_log="" # "전체 파일 확장자" 로깅용 변수

  if [[ "$filename" == *.* ]]; then
    _ext_val="${filename##*.}"
    if [ -n "$_ext_val" ]; then
      lowercase_ext=$(echo "$_ext_val" | tr '[:upper:]' '[:lower:]')
      current_file_extension_for_log="$lowercase_ext"

      parser_type_for_this_file=""
      is_hardcoded_parser_type=0

      if [[ "$lowercase_ext" == "c" ]]; then
          parser_type_for_this_file="C_LANG"
          is_hardcoded_parser_type=1
      elif [[ "$lowercase_ext" == "cpp" ]]; then
          parser_type_for_this_file="CPP_LANG"
          is_hardcoded_parser_type=1
      fi

      properties_defined_parser_type=""
      for ((i=0; i<${#ext_keys[@]}; i++)); do
          if [[ "${ext_keys[i]}" == "$lowercase_ext" ]]; then
              properties_defined_parser_type="${parser_values[i]}"
              if [[ $is_hardcoded_parser_type -eq 0 ]]; then # 하드코딩 아니면 properties 정의 사용
                  parser_type_for_this_file="$properties_defined_parser_type"
              fi
              break
          fi
      done

      if [ -n "$parser_type_for_this_file" ]; then
          # 모든 파서 유형 (하드코딩된 C/C++ 포함) 기록 -> "컴파일러 연관" 섹션에서 사용
          echo "$parser_type_for_this_file" >> "$PARSER_TYPE_COUNT_TEMP_FILE"
          echo "${parser_type_for_this_file}:${lowercase_ext}" >> "$FOUND_PARSER_EXT_TEMP_FILE"
      fi

      # Properties 파일에 정의된 파서 유형만 별도 기록 -> "Fortify 지원 확장자" 섹션에서 사용
      if [ -n "$properties_defined_parser_type" ]; then
          echo "$properties_defined_parser_type" >> "$PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE"
          echo "${properties_defined_parser_type}:${lowercase_ext}" >> "$PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE"
      fi

    else
      current_file_extension_for_log="(empty extension)"
    fi
  else
    current_file_extension_for_log="(no extension)"
  fi
  echo "$current_file_extension_for_log" >> "$EXTENSIONS_TEMP_FILE" # 순수 확장자만 기록
done

sort "$EXTENSIONS_TEMP_FILE" | uniq -c | awk '{printf "%5s | %s\n", $1, $2}' | sort -k1nr -k3

# --- "Fortify 지원 확장자" 섹션 ---
found_properties_based_output=0
if [ -s "$PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE" ]; then
    total_properties_based_files=0
    sorted_properties_based_parser_counts_lines=()
    while IFS= read -r line; do
        sorted_properties_based_parser_counts_lines+=("$line")
    done < <(sort "$PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE" | uniq -c | sort -k1nr)

    for line in "${sorted_properties_based_parser_counts_lines[@]}"; do
        if [[ $found_properties_based_output -eq 0 ]]; then
            echo "---------------------------------------------"
            echo "Fortify 지원 확장자:"
            echo "---------------------------------------------"
            found_properties_based_output=1
        fi
        count_and_parser_type=$(echo "$line" | sed 's/^[[:space:]]*//')
        count=$(echo "$count_and_parser_type" | awk '{print $1}')
        parser_type_name=$(echo "$count_and_parser_type" | awk '{print $2}')
        total_properties_based_files=$((total_properties_based_files + count))

        actual_found_extensions_str=""
        if [ -s "$PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE" ]; then
            found_ext_list=$(grep "^${parser_type_name}:" "$PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE" | cut -d':' -f2- | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
            if [ -n "$found_ext_list" ]; then
                actual_found_extensions_str=" ($found_ext_list)"
            fi
        fi
        printf "%5s | %s%s\n" "$count" "$parser_type_name" "$actual_found_extensions_str"
    done

    if [[ $found_properties_based_output -eq 1 ]]; then
        echo "---------------------------------------------"
        echo "Fortify 지원 확장자 총 개수: $total_properties_based_files"
    fi
fi

# --- "컴파일러 대상 확장자" 섹션 ---
COMPILER_ASSOCIATED_PARSER_TYPES=(
    "SCALA" "JAVA" "CSHARP" "VB" "SWIFT" "GO" "KOTLIN" "C_LANG" "CPP_LANG"
)
total_compiler_associated_files=0
found_compiler_associated_output=0
all_parser_counts_lines=() # 모든 파서 유형 (하드코딩 포함)에 대한 집계 결과

if [ -s "$PARSER_TYPE_COUNT_TEMP_FILE" ]; then
    while IFS= read -r line; do
        all_parser_counts_lines+=("$line")
    done < <(sort "$PARSER_TYPE_COUNT_TEMP_FILE" | uniq -c | sort -k1nr)
fi

if [ ${#all_parser_counts_lines[@]} -gt 0 ]; then
    for line_from_all_parser_counts in "${all_parser_counts_lines[@]}"; do
        count_and_ptype=$(echo "$line_from_all_parser_counts" | sed 's/^[[:space:]]*//')
        current_count=$(echo "$count_and_ptype" | awk '{print $1}')
        current_parser_type_name=$(echo "$count_and_ptype" | awk '{print $2}')

        if [[ "$current_parser_type_name" == "(*"* ]]; then
            continue
        fi

        is_compiler_associated=0
        for ca_ptype in "${COMPILER_ASSOCIATED_PARSER_TYPES[@]}"; do
            if [[ "$current_parser_type_name" == "$ca_ptype" ]]; then
                is_compiler_associated=1
                break
            fi
        done

        if [[ $is_compiler_associated -eq 1 ]];
        then
            if [[ $found_compiler_associated_output -eq 0 ]]; then
                echo "---------------------------------------------"
                echo "컴파일러 대상 확장자:"
                echo "---------------------------------------------"
                found_compiler_associated_output=1
            fi
            total_compiler_associated_files=$((total_compiler_associated_files + current_count))
            current_found_extensions_str_for_compiler_section=""
            if [ -s "$FOUND_PARSER_EXT_TEMP_FILE" ]; then # 모든 파서:확장자 매핑 파일 사용
                found_ext_list_for_ca=$(grep "^${current_parser_type_name}:" "$FOUND_PARSER_EXT_TEMP_FILE" | cut -d':' -f2- | sort -u | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                if [ -n "$found_ext_list_for_ca" ]; then
                    current_found_extensions_str_for_compiler_section=" ($found_ext_list_for_ca)"
                fi
            fi
            printf "%5s | %s%s\n" "$current_count" "$current_parser_type_name" "$current_found_extensions_str_for_compiler_section"
        fi
    done
fi

if [[ $found_compiler_associated_output -eq 1 ]]; then
    echo "---------------------------------------------"
    echo "컴파일러 대상 확장자 총 개수: $total_compiler_associated_files"
fi

echo "---------------------------------------------"
echo "분석 완료."