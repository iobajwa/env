@echo off

set project_name=
set project_path=
set jump_to_halwayi_scripts=false

	rem Parse command line switches to determine project name, flags, etc.
:pro_parse_parameter_flags
		IF [%1]==[] (
			GOTO pro_end_parse
		) else IF [%1]==[s] (
			set jump_to_halwayi_scripts=true
		) else (
			set project_name=%1
		)
	SHIFT
	GOTO pro_parse_parameter_flags
:pro_end_parse

if [%project_name%]==[] (
	echo USAGE: project 'project_name'
	goto pro_quit_script
)

set project_path="d:\dev\%project_name%"

if not exist %project_path% (
	echo project '%project_name%' could not be found.
	goto pro_quit_script
) 

d:
cd %project_path%
set var=
set platform=
if exist environment.bat (
	call environment.bat
) else (
	set ScriptsRoot=xyz
)

if exist %ScriptsRoot% (
	if [%jump_to_halwayi_scripts%]==[true] (
		cd %ScriptsRoot%
	)
)

:pro_quit_script
echo .