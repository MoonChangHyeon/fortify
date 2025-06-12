@echo off
setlocal enabledelayedexpansion

REM --- Configuration ---
REM Fortify 설정 파일 경로 (사용자 환경에 맞게 수정 필요)
set "FORTIFY_PROPERTIES_FILE=%USERPROFILE%\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"
REM The above path was taken from the shell script. Adjust if your user profile path is different or the file is elsewhere.
REM For example: set "FORTIFY_PROPERTIES_FILE=C:\Users\YourUser\Documents\Workspce\SCA\24.4\Core\config\fortify-sca.properties"


REM --- Script Usage and Input Validation ---
if "%~1"=="" (
    echo 오류: 폴더 경로를 입력해주세요.
    echo 사용법: %~n0 ^<폴더_경로^>
    exit /b 1
)
set "TARGET_DIR=%~1"
if not exist "%TARGET_DIR%\" (
    echo 오류: '%TARGET_DIR%'는 유효한 디렉토리가 아닙니다.
    exit /b 1
)
pushd "%TARGET_DIR%" 2>nul || (
    echo 오류: '%TARGET_DIR%' 디렉토리로 변경할 수 없습니다.
    exit /b 1
)
popd
set "TARGET_DIR=%~f1"


echo 선택된 폴더: %TARGET_DIR%

REM --- Temporary Files ---
set "TEMP_DIR=%TEMP%"
set "RAND_SUFFIX=%RANDOM%%RANDOM%"
set "EXTENSIONS_TEMP_FILE=%TEMP_DIR%\ext_list_%RAND_SUFFIX%.tmp"
set "PARSER_TYPE_COUNT_TEMP_FILE=%TEMP_DIR%\parser_type_counts_%RAND_SUFFIX%.tmp"
set "FOUND_PARSER_EXT_TEMP_FILE=%TEMP_DIR%\found_parser_ext_%RAND_SUFFIX%.tmp"
set "PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE=%TEMP_DIR%\prop_parser_counts_%RAND_SUFFIX%.tmp"
set "PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE=%TEMP_DIR%\prop_found_ext_%RAND_SUFFIX%.tmp"

REM --- Cleanup ---
REM This is a simple cleanup. For more robust cleanup on error, more complex trapping would be needed.
REM We will delete these at the end of the script.

REM --- Initialize Arrays/Counters for Properties ---
set "prop_count=0"

echo ---------------------------------------------
echo  개수  ^| 전체 파일 확장자
echo ---------------------------------------------

REM --- Read Fortify Properties File ---
if exist "%FORTIFY_PROPERTIES_FILE%" (
    for /f "tokens=1,* delims==" %%A in ('findstr /B /C:"com.fortify.sca.fileextensions." "%FORTIFY_PROPERTIES_FILE%"') do (
        set "key=%%A"
        set "value=%%B"

        set "ext_key_raw=!key:com.fortify.sca.fileextensions.=!"
        call :toLower "!ext_key_raw!" ext_key_lower
        
        set "parser_type_raw=!value!"
        set "parser_type=!parser_type_raw: =!" REM Remove spaces

        if defined ext_key_lower if defined parser_type (
            set /a prop_count+=1
            set "ext_keys[!prop_count!]=!ext_key_lower!"
            set "parser_values[!prop_count!]=!parser_type!"
        )
    )
) else (
    echo 경고: Fortify 설정 파일(%FORTIFY_PROPERTIES_FILE%)을 찾을 수 없습니다. 파서 유형별 개수는 제공되지 않습니다.
)

REM --- Process Files in Target Directory ---
for /R "%TARGET_DIR%" %%F in (*.*) do (
    set "file_path=%%F"
    set "filename=%%~nxF"
    set "current_file_extension_for_log="

    set "file_ext=%%~xF"
    if defined file_ext (
        set "_ext_val=!file_ext:~1!" REM Remove leading dot
        if defined _ext_val (
            call :toLower "!_ext_val!" lowercase_ext
            set "current_file_extension_for_log=!lowercase_ext!"

            set "parser_type_for_this_file="
            set "is_hardcoded_parser_type=0"

            if /I "!lowercase_ext!"=="c" (
                set "parser_type_for_this_file=C_LANG"
                set "is_hardcoded_parser_type=1"
            ) else if /I "!lowercase_ext!"=="cpp" (
                set "parser_type_for_this_file=CPP_LANG"
                set "is_hardcoded_parser_type=1"
            )

            set "properties_defined_parser_type="
            if %prop_count% GTR 0 (
                for /L %%i in (1,1,%prop_count%) do (
                    if "!ext_keys[%%i]!"=="!lowercase_ext!" (
                        set "properties_defined_parser_type=!parser_values[%%i]!"
                        if !is_hardcoded_parser_type! EQU 0 (
                            set "parser_type_for_this_file=!properties_defined_parser_type!"
                        )
                        goto :found_prop_ext_%%F
                    )
                )
            )
            :found_prop_ext_%%F

            if defined parser_type_for_this_file (
                echo !parser_type_for_this_file!>>"%PARSER_TYPE_COUNT_TEMP_FILE%"
                echo !parser_type_for_this_file!:!lowercase_ext!>>"%FOUND_PARSER_EXT_TEMP_FILE%"
            )

            if defined properties_defined_parser_type (
                echo !properties_defined_parser_type!>>"%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%"
                echo !properties_defined_parser_type!:!lowercase_ext!>>"%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%"
            )
        ) else (
            set "current_file_extension_for_log=(empty extension)"
        )
    ) else (
        set "current_file_extension_for_log=(no extension)"
    )
    if defined current_file_extension_for_log (
        echo !current_file_extension_for_log!>>"%EXTENSIONS_TEMP_FILE%"
    )
)

REM --- Display "전체 파일 확장자" ---
set "sorted_ext_temp=%TEMP_DIR%\sorted_ext_%RAND_SUFFIX%.tmp"
set "uniq_c_ext_temp=%TEMP_DIR%\uniq_c_ext_%RAND_SUFFIX%.tmp"
set "formatted_ext_temp=%TEMP_DIR%\formatted_ext_%RAND_SUFFIX%.tmp"

if exist "%EXTENSIONS_TEMP_FILE%" (
    sort "%EXTENSIONS_TEMP_FILE%" /O "%sorted_ext_temp%"
    call :emulateUniqC "%sorted_ext_temp%" "%uniq_c_ext_temp%"
    call :formatAwkStyle "%uniq_c_ext_temp%" "%formatted_ext_temp%"
    REM Sort by count (desc), then extension (desc for ties - diff from shell's asc)
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
    REM Sort by count (desc), then parser_type (asc for ties)
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

        set "actual_found_extensions_str="
        if exist "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%" (
            call :getFormattedExtensionList "!parser_type_name!" "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%" actual_found_extensions_str
        )
        
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
    REM Sort by count (desc), then parser_type (asc for ties)
    call :customSortCountDescValueAsc "%uniq_c_all_parser_temp%" "%final_sorted_all_parser_temp%"

    for /f "tokens=1,*" %%N in (%final_sorted_all_parser_temp%) do (
        set "current_count=%%N"
        set "current_parser_type_name=%%O"

        REM if [[ "$current_parser_type_name" == "(*"* ]]; then continue; fi
        set "prefix_check=!current_parser_type_name:~0,2!"
        if "!prefix_check!" == "(*" goto :skip_compiler_parser_type

        set "is_compiler_associated=0"
        if "!COMPILER_ASSOCIATED_PARSER_TYPES:,%current_parser_type_name%,=!" NEQ "!COMPILER_ASSOCIATED_PARSER_TYPES!" (
            set "is_compiler_associated=1"
        )

        if !is_compiler_associated! EQU 1 (
            if !found_compiler_associated_output! EQU 0 (
                echo ---------------------------------------------
                echo 컴파일러 대상 확장자:
                echo ---------------------------------------------
                set "found_compiler_associated_output=1"
            )
            set /a total_compiler_associated_files+=!current_count!
            
            set "current_found_extensions_str_for_compiler_section="
            if exist "%FOUND_PARSER_EXT_TEMP_FILE%" (
                 call :getFormattedExtensionList "!current_parser_type_name!" "%FOUND_PARSER_EXT_TEMP_FILE%" current_found_extensions_str_for_compiler_section
            )
            
            set "padded_current_count=     !current_count!"
            set "padded_current_count=!padded_current_count:~-5!"
            echo !padded_current_count! ^| !current_parser_type_name!!current_found_extensions_str_for_compiler_section!
        )
        :skip_compiler_parser_type
    )
)

if !found_compiler_associated_output! EQU 1 (
    echo ---------------------------------------------
    echo 컴파일러 대상 확장자 총 개수: !total_compiler_associated_files!
)

echo ---------------------------------------------
echo 분석 완료.

goto :cleanup_and_exit

REM --- Subroutines ---

:toLower
setlocal
set "str_in=%~1"
set "var_to_set_out=%~2"
set "alphabet_upper=ABCDEFGHIJKLMNOPQRSTUVWXYZ"
set "alphabet_lower=abcdefghijklmnopqrstuvwxyz"
set "result_str=%str_in%"
REM This is a simplified toLower for typical ASCII. Does not handle all Unicode.
for /L %%i in (0,1,25) do (
    call set "char_upper=%%alphabet_upper:~%%i,1%%"
    call set "char_lower=%%alphabet_lower:~%%i,1%%"
    set "result_str=!result_str:%char_upper%=%char_lower%!"
)
endlocal & set "%var_to_set_out%=%result_str%"
goto :eof

:emulateUniqC
REM Input: %1 = sorted input file, %2 = output file (count item)
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
REM Input: %1 = file with "count item", %2 = output file ("     count | item")
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
REM Input: %1 = file with "count value", %2 = output file sorted by count (desc) then value (asc)
setlocal
set "input_file_cv=%~1"
set "output_file_sorted_cv=%~2"
set "intermediate_sort_file=%TEMP_DIR%\custom_sort_intermediate_%RAND_SUFFIX%.tmp"

(
    for /f "usebackq tokens=1,*" %%N in ("%input_file_cv%") do (
        set "count_val=%%N"
        set "item_val=%%O"
        REM Pad count for sorting (e.g. 5 digits)
        set "padded_count=00000!count_val!"
        set "padded_count=!padded_count:~-5!"
        REM Create a sort key for descending count: MAX_NUM - count
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
        REM Remove leading zeros from count for display
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
REM Input: %1 = parser_type_name, %2 = file_to_search (parser:ext), %3 = output variable name for "(ext1, ext2)"
setlocal
set "p_parser_type_name=%~1"
set "p_file_to_search=%~2"
set "p_output_var_name=%~3"

set "extensions_list_str="
set "temp_ext_for_parser_list=%TEMP_DIR%\temp_ext_for_parser_list_%RAND_SUFFIX%.txt"
set "sorted_unique_ext_for_parser_list=%TEMP_DIR%\sorted_unique_ext_for_parser_list_%RAND_SUFFIX%.txt"

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


:cleanup_and_exit
REM Delete temporary files
if exist "%EXTENSIONS_TEMP_FILE%" del "%EXTENSIONS_TEMP_FILE%"
if exist "%PARSER_TYPE_COUNT_TEMP_FILE%" del "%PARSER_TYPE_COUNT_TEMP_FILE%"
if exist "%FOUND_PARSER_EXT_TEMP_FILE%" del "%FOUND_PARSER_EXT_TEMP_FILE%"
if exist "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%" del "%PROPERTIES_BASED_PARSER_TYPE_COUNT_TEMP_FILE%"
if exist "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%" del "%PROPERTIES_BASED_FOUND_PARSER_EXT_TEMP_FILE%"

if exist "%TEMP_DIR%\sorted_ext_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\sorted_ext_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\uniq_c_ext_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\uniq_c_ext_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\formatted_ext_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\formatted_ext_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\sorted_prop_parser_counts_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\sorted_prop_parser_counts_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\uniq_c_prop_parser_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\uniq_c_prop_parser_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\final_sorted_prop_parser_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\final_sorted_prop_parser_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\sorted_all_parser_counts_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\sorted_all_parser_counts_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\uniq_c_all_parser_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\uniq_c_all_parser_%RAND_SUFFIX%.tmp"
if exist "%TEMP_DIR%\final_sorted_all_parser_%RAND_SUFFIX%.tmp" del "%TEMP_DIR%\final_sorted_all_parser_%RAND_SUFFIX%.tmp"
REM Any other specific temp files from subroutines using RAND_SUFFIX will also be covered if they follow the pattern.

endlocal
exit /b 0
