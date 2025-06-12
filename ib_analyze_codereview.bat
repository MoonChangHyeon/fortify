@echo off
setlocal enabledelayedexpansion

REM --- Configuration ---
REM Fortify 설정 파일 경로 (사용자 환경에 맞게 수정 필요)
set "FORTIFY_PROPERTIES_FILE=%USERPROFILE%\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"

REM --- Script Usage and Input Validation ---
if "%~1"=="" (
    echo 오류: 폴더 경로를 입력해주세요.
    echo 사용법: %~n0 ^<폴더_경로^>
    goto :error_exit
)
set "TARGET_DIR=%~1"
if not exist "%TARGET_DIR%\" (
    echo 오류: '%TARGET_DIR%'는 유효한 디렉토리가 아닙니다.
    goto :error_exit
)
rem pushd/popd in case path is relative, get full path
pushd "%TARGET_DIR%" 2>nul || (
    echo 오류: '%TARGET_DIR%' 디렉토리로 변경할 수 없습니다.
    goto :error_exit
)
set "TARGET_DIR=%CD%"
popd

echo 선택된 폴더: %TARGET_DIR%

REM --- Temporary Files ---
set "TEMP_DIR=%TEMP%"
set "RAND_SUFFIX=%RANDOM%%RANDOM%"
set "EXTENSIONS_TEMP_FILE=%TEMP_DIR%\ext_list_%RAND_SUFFIX%.tmp"
set "PARSER_TYPE_COUNT_TEMP_FILE=%TEMP_DIR%\parser_type_counts_%RAND_SUFFIX%.tmp"
set "FOUND_PARSER_EXT_TEMP_FILE=%TEMP_DIR%\found_parser_ext_%RAND_SUFFIX%.tmp"
set "PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE=%TEMP_DIR%\prop_parser_counts_%RAND_SUFFIX%.tmp"
set "PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE=%TEMP_DIR%\prop_found_ext_%RAND_SUFFIX%.tmp"

REM --- Read Fortify Properties File (Improved Performance) ---
echo Fortify 설정 파일을 읽는 중...
if exist "%FORTIFY_PROPERTIES_FILE%" (
    for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"com.fortify.sca.fileextensions." "%FORTIFY_PROPERTIES_FILE%"') do (
        set "key=%%A"
        set "value=%%B"
        set "ext_key_raw=!key:com.fortify.sca.fileextensions.=!"
        call :toLower "!ext_key_raw!" ext_key_lower
        set "parser_type_raw=!value!"
        set "parser_type=!parser_type_raw: =!"
        if defined ext_key_lower if defined parser_type (
            set "prop_parser.!ext_key_lower!=!parser_type!"
        )
    )
) else (
    echo 경고: Fortify 설정 파일(%FORTIFY_PROPERTIES_FILE%)을 찾을 수 없습니다. 파서 유형별 개수는 제공되지 않습니다.
)

REM --- Process Files in Target Directory (Improved Performance) ---
echo 대상 폴더의 파일들을 분석하는 중...
(
    for /R "%TARGET_DIR%" %%F in (*.*) do (
        set "file_ext=%%~xF"
        if defined file_ext (
            set "_ext_val=!file_ext:~1!"
            if defined _ext_val (
                call :toLower "!_ext_val!" lowercase_ext

                set "parser_type_for_this_file="
                if /I "!lowercase_ext!"=="c" (
                    set "parser_type_for_this_file=C_LANG"
                ) else if /I "!lowercase_ext!"=="cpp" (
                    set "parser_type_for_this_file=CPP_LANG"
                )

                set "properties_defined_parser_type="
                if defined prop_parser.!lowercase_ext! (
                    set "properties_defined_parser_type=!prop_parser.!lowercase_ext!!"
                    if not defined parser_type_for_this_file (
                        set "parser_type_for_this_file=!properties_defined_parser_type!"
                    )
                )

                if defined parser_type_for_this_file (
                    echo !parser_type_for_this_file!
                    echo !parser_type_for_this_file!:!lowercase_ext! >>"%FOUND_PARSER_EXT_TEMP_FILE%"
                )
                if defined properties_defined_parser_type (
                    echo !properties_defined_parser_type! >>"%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%"
                    echo !properties_defined_parser_type!:!lowercase_ext! >>"%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%"
                )
                echo !lowercase_ext! >>"%EXTENSIONS_TEMP_FILE%"
            ) else (
                echo (empty extension) >>"%EXTENSIONS_TEMP_FILE%"
            )
        ) else (
            echo (no extension) >>"%EXTENSIONS_TEMP_FILE%"
        )
    )
) >"%PARSER_TYPE_COUNT_TEMP_FILE%"

echo 분석 결과 출력 중...
echo.
echo ---------------------------------------------
echo  개수  ^| 전체 파일 확장자
echo ---------------------------------------------
set "sorted_ext_temp=%TEMP_DIR%\sorted_ext_%RAND_SUFFIX%.tmp"
set "uniq_c_ext_temp=%TEMP_DIR%\uniq_c_ext_%RAND_SUFFIX%.tmp"
set "formatted_ext_temp=%TEMP_DIR%\formatted_ext_%RAND_SUFFIX%.tmp"

if exist "%EXTENSIONS_TEMP_FILE%" (
    sort "%EXTENSIONS_TEMP_FILE%" /O "%sorted_ext_temp%"
    call :emulateUniqC "%sorted_ext_temp%" "%uniq_c_ext_temp%"
    call :formatAwkStyle "%uniq_c_ext_temp%" "%formatted_ext_temp%"
    sort /R "%formatted_ext_temp%"
)

REM --- "Fortify 지원 확장자" 섹션 ---
set "found_properties_based_output=0"
if exist "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%" (
    set "total_properties_based_files=0"
    set "sorted_prop_parser_counts_temp=%TEMP_DIR%\sorted_prop_parser_counts_%RAND_SUFFIX%.tmp"
    set "uniq_c_prop_parser_temp=%TEMP_DIR%\uniq_c_prop_parser_%RAND_SUFFIX%.tmp"
    set "final_sorted_prop_parser_temp=%TEMP_DIR%\final_sorted_prop_parser_%RAND_SUFFIX%.tmp"

    sort "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%" /O "%sorted_prop_parser_counts_temp%"
    call :emulateUniqC "%sorted_prop_parser_counts_temp%" "%uniq_c_prop_parser_temp%"
    call :customSortCountDescValueAsc "%uniq_c_prop_parser_temp%" "%final_sorted_prop_parser_temp%"

    for /f "tokens=1,*" %%N in (%final_sorted_prop_parser_temp%) do (
        set "count=%%N"
        set "parser_type_name=%%O"
        if !found_properties_based_output! EQU 0 (
            echo ---------------------------------------------
            echo Fortify 지원 확장자:
            echo ---------------------------------------------
            set "found_properties_based_output=1"
        )
        set /a total_properties_based_files+=!count!
        call :getFormattedExtensionList "!parser_type_name!" "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%" actual_found_extensions_str
        set "padded_count=     !count!"
        set "padded_count=!padded_count:~-5!"
        echo !padded_count! ^| !parser_type_name!!actual_found_extensions_str!
    )
    if !found_properties_based_output! EQU 1 (
        echo ---------------------------------------------
        echo Fortify 지원 확장자 총 개수: !total_properties_based_files!
    )
)

REM --- "컴파일러 대상 확장자" 섹션 ---
set "COMPILER_ASSOCIATED_PARSER_TYPES=,SCALA,JAVA,CSHARP,VB,SWIFT,GO,KOTLIN,C_LANG,CPP_LANG,"
set "total_compiler_associated_files=0"
set "found_compiler_associated_output=0"
if exist "%PARSER_TYPE_COUNT_TEMP_FILE%" (
    set "sorted_all_parser_counts_temp=%TEMP_DIR%\sorted_all_parser_counts_%RAND_SUFFIX%.tmp"
    set "uniq_c_all_parser_temp=%TEMP_DIR%\uniq_c_all_parser_%RAND_SUFFIX%.tmp"
    set "final_sorted_all_parser_temp=%TEMP_DIR%\final_sorted_all_parser_%RAND_SUFFIX%.tmp"

    sort "%PARSER_TYPE_COUNT_TEMP_FILE%" /O "%sorted_all_parser_counts_temp%"
    call :emulateUniqC "%sorted_all_parser_counts_temp%" "%uniq_c_all_parser_temp%"
    call :customSortCountDescValueAsc "%uniq_c_all_parser_temp%" "%final_sorted_all_parser_temp%"

    for /f "tokens=1,*" %%N in (%final_sorted_all_parser_temp%) do (
        set "current_count=%%N"
        set "current_parser_type_name=%%O"
        set "prefix_check=!current_parser_type_name:~0,2!"
        if "!prefix_check!" NEQ "(*" (
            if "!COMPILER_ASSOCIATED_PARSER_TYPES:,%current_parser_type_name%,=!" NEQ "!COMPILER_ASSOCIATED_PARSER_TYPES!" (
                if !found_compiler_associated_output! EQU 0 (
                    echo ---------------------------------------------
                    echo 컴파일러 대상 확장자:
                    echo ---------------------------------------------
                    set "found_compiler_associated_output=1"
                )
                set /a total_compiler_associated_files+=!current_count!
                call :getFormattedExtensionList "!current_parser_type_name!" "%FOUND_PARSER_EXT_TEMP_FILE%" current_found_extensions_str_for_compiler_section
                set "padded_current_count=     !current_count!"
                set "padded_current_count=!padded_current_count:~-5!"
                echo !padded_current_count! ^| !current_parser_type_name!!current_found_extensions_str_for_compiler_section!
            )
        )
    )
)
if !found_compiler_associated_output! EQU 1 (
    echo ---------------------------------------------
    echo 컴파일러 대상 확장자 총 개수: !total_compiler_associated_files!
)

echo ---------------------------------------------
echo 분석 완료.
goto :cleanup_and_exit

REM --- Subroutines (Unchanged) ---
:toLower
setlocal
set "str_in=%~1"
set "var_to_set_out=%~2"
set "alphabet_upper=ABCDEFGHIJKLMNOPQRSTUVWXYZ"
set "alphabet_lower=abcdefghijklmnopqrstuvwxyz"
set "result_str=%str_in%"
for /L %%i in (0,1,25) do (
    call set "char_upper=%%alphabet_upper:~%%i,1%%"
    call set "char_lower=%%alphabet_lower:~%%i,1%%"
    set "result_str=!result_str:%char_upper%=%char_lower%!"
)
endlocal & set "%var_to_set_out%=%result_str%"
goto :eof

:emulateUniqC
setlocal
set "sorted_input_file=%~1"
set "output_file=%~2"
(
    set "prev_line="
    set "count=0"
    for /f "usebackq delims=" %%L in ("%sorted_input_file%") do (
        if defined prev_line (
            if "!prev_line!" NEQ "%%L" (
                if !count! GTR 0 echo !count! !prev_line!
                set "count=1"
            ) else (
                set /a count+=1
            )
        ) else (
            set "count=1"
        )
        set "prev_line=%%L"
    )
    if %count% GTR 0 if defined prev_line echo !count! !prev_line!
) > "%output_file%"
endlocal
goto :eof

:formatAwkStyle
setlocal
set "input_file_uniq_c=%~1"
set "output_file_formatted=%~2"
(
    for /f "usebackq tokens=1,*" %%N in ("%input_file_uniq_c%") do (
        set "num=%%N"
        set "item=%%O"
        set "padded_num=     !num!"
        set "padded_num=!padded_num:~-5!"
        echo !padded_num! ^| !item!
    )
) > "%output_file_formatted%"
endlocal
goto :eof

:customSortCountDescValueAsc
setlocal
set "input_file_cv=%~1"
set "output_file_sorted_cv=%~2"
set "intermediate_sort_file=%TEMP_DIR%\custom_sort_intermediate_%RAND_SUFFIX%.tmp"
(
    for /f "usebackq tokens=1,*" %%N in ("%input_file_cv%") do (
        set "count_val=%%N"
        set "item_val=%%O"
        set "padded_count=00000!count_val!"
        set "padded_count=!padded_count:~-5!"
        set /a "sort_key_count = 99999 - !count_val!"
        set "padded_sort_key_count=00000!sort_key_count!"
        set "padded_sort_key_count=!padded_sort_key_count:~-5!"
        echo !padded_sort_key_count! !item_val! !padded_count! !item_val!
    )
) > "%intermediate_sort_file%"
(
    for /f "usebackq tokens=3,4" %%P in ('sort "%intermediate_sort_file%"') do (
        set "original_count_str=%%P"
        set "original_item_str=%%Q"
        set "display_count="
        for /l %%z in (0,1,4) do (
            if not "!display_count!"=="" (
                set "display_count=!display_count!!original_count_str:~%%z,1!"
            ) else (
                if "!original_count_str:~%%z,1!" NEQ "0" (
                    set "display_count=!original_count_str:~%%z,1!"
                )
            )
        )
        if not defined display_count set "display_count=0"
        echo !display_count! !original_item_str!
    )
) > "%output_file_sorted_cv%"
if exist "%intermediate_sort_file%" del "%intermediate_sort_file%"
endlocal
goto :eof

:getFormattedExtensionList
setlocal
set "p_parser_type_name=%~1"
set "p_file_to_search=%~2"
set "p_output_var_name=%~3"
set "temp_ext_for_parser_list=%TEMP_DIR%\temp_ext_for_parser_list_%RANDOM%.txt"
set "sorted_unique_ext_for_parser_list=%TEMP_DIR%\sorted_unique_ext_for_parser_list_%RANDOM%.txt"
(for /f "usebackq tokens=1,* delims=:" %%s in ('findstr /B /L /C:"%p_parser_type_name%:" "%p_file_to_search%"') do (
    if /I "%%s"=="%p_parser_type_name%" (
        echo %%t
    )
)) > "%temp_ext_for_parser_list%"
sort "%temp_ext_for_parser_list%" /UNIQUE /O "%sorted_unique_ext_for_parser_list%"
set "built_ext_list="
set "first_in_list=1"
for /f "usebackq delims=" %%e in ("%sorted_unique_ext_for_parser_list%") do (
    if !first_in_list! == 1 (
        set "built_ext_list=%%e"
        set "first_in_list=0"
    ) else (
        set "built_ext_list=!built_ext_list!, %%e"
    )
)
if exist "%temp_ext_for_parser_list%" del "%temp_ext_for_parser_list%"
if exist "%sorted_unique_ext_for_parser_list%" del "%sorted_unique_ext_for_parser_list%"
if defined built_ext_list (
    endlocal & set "%p_output_var_name%= (!built_ext_list!)"
) else (
    endlocal & set "%p_output_var_name%="
)
goto :eof

:error_exit
set "errorlevel=1"
goto :cleanup_and_exit

:cleanup_and_exit
if exist "%EXTENSIONS_TEMP_FILE%" del "%EXTENSIONS_TEMP_FILE%"
if exist "%PARSER_TYPE_COUNT_TEMP_FILE%" del "%PARSER_TYPE_COUNT_TEMP_FILE%"
if exist "%FOUND_PARSER_EXT_TEMP_FILE%" del "%FOUND_PARSER_EXT_TEMP_FILE%"
if exist "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%" del "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%"
if exist "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%" del "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%"
if exist "%TEMP_DIR%\sorted_ext_*.tmp" del "%TEMP_DIR%\sorted_ext_*.tmp"
if exist "%TEMP_DIR%\uniq_c_ext_*.tmp" del "%TEMP_DIR%\uniq_c_ext_*.tmp"
if exist "%TEMP_DIR%\formatted_ext_*.tmp" del "%TEMP_DIR%\formatted_ext_*.tmp"
if exist "%TEMP_DIR%\sorted_prop_parser_counts_*.tmp" del "%TEMP_DIR%\sorted_prop_parser_counts_*.tmp"
if exist "%TEMP_DIR%\uniq_c_prop_parser_*.tmp" del "%TEMP_DIR%\uniq_c_prop_parser_*.tmp"
if exist "%TEMP_DIR%\final_sorted_prop_parser_*.tmp" del "%TEMP_DIR%\final_sorted_prop_parser_*.tmp"
if exist "%TEMP_DIR%\sorted_all_parser_counts_*.tmp" del "%TEMP_DIR%\sorted_all_parser_counts_*.tmp"
if exist "%TEMP_DIR%\uniq_c_all_parser_*.tmp" del "%TEMP_DIR%\uniq_c_all_parser_*.tmp"
if exist "%TEMP_DIR%\final_sorted_all_parser_*.tmp" del "%TEMP_DIR%\final_sorted_all_parser_*.tmp"

endlocal
exit /b %errorlevel%