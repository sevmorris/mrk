on run
	activate
	display dialog "Audio Opener asks where to open audio files before opening them." & return & return & "To use it, open an audio file in Finder." buttons {"OK"} default button "OK" with title "Audio Opener"
end run

on open theFiles
	set n to count of theFiles
	if n is 1 then
		set prompt to "Open “" & my fileName(item 1 of theFiles) & "” in:"
	else
		set prompt to "Open " & n & " audio files in:"
	end if
	activate
	set choice to button returned of (display dialog prompt buttons {"Cancel", "QuickTime Player", "Music"} default button "Cancel" cancel button "Cancel" with title "Open Audio" with icon note)
	if choice is "Music" then
		set appName to "Music"
	else
		set appName to "QuickTime Player"
	end if
	set args to ""
	repeat with f in theFiles
		set args to args & " " & quoted form of POSIX path of f
	end repeat
	do shell script "open -a " & quoted form of appName & args
end open

on fileName(f)
	set p to POSIX path of f
	set AppleScript's text item delimiters to "/"
	set nm to last text item of p
	set AppleScript's text item delimiters to ""
	return nm
end fileName
