-- Media Opener asks where to open an audio or video file before opening it.
-- Cancel is the default button, so Return or Escape opens nothing.
--
-- Music is offered only when Music can play every file: Music adds what it
-- opens to the library, which is what Media Opener was made to stop. Any other
-- file is offered VLC, which plays the containers QuickTime Player cannot
-- (Matroska, WebM, FLAC), when VLC is installed.

property musicExtensions : {"mp3", "m4a", "m4p", "m4b", "wav", "aif", "aiff", "aifc", "mp2"}
property vlcApp : "/Applications/VLC.app"

on run
	activate
	display dialog "Media Opener asks where to open audio and video files before opening them." & return & return & "To use it, open an audio or video file in Finder." buttons {"OK"} default button "OK" with title "Media Opener"
end run

on open theFiles
	set n to count of theFiles
	set allMusic to true
	repeat with f in theFiles
		if musicExtensions does not contain my extensionOf(f) then set allMusic to false
	end repeat

	if allMusic then
		set choices to {"Cancel", "QuickTime Player", "Music"}
	else if my hasVLC() then
		set choices to {"Cancel", "VLC", "QuickTime Player"}
	else
		set choices to {"Cancel", "QuickTime Player"}
	end if

	if n is 1 then
		set prompt to "Open “" & my fileName(item 1 of theFiles) & "” in:"
	else
		set prompt to "Open " & n & " files in:"
	end if
	activate
	set choice to button returned of (display dialog prompt buttons choices default button "Cancel" cancel button "Cancel" with title "Open Media" with icon note)
	if choice is "Music" then
		set target to "-a " & quoted form of "Music"
	else if choice is "VLC" then
		set target to "-a " & quoted form of vlcApp
	else
		set target to "-a " & quoted form of "QuickTime Player"
	end if

	set args to ""
	repeat with f in theFiles
		set args to args & " " & quoted form of POSIX path of f
	end repeat
	do shell script "open " & target & args
end open

on hasVLC()
	try
		do shell script "test -d " & quoted form of vlcApp
		return true
	on error
		return false
	end try
end hasVLC

on fileName(f)
	set p to POSIX path of f
	set AppleScript's text item delimiters to "/"
	set nm to last text item of p
	set AppleScript's text item delimiters to ""
	return nm
end fileName

on extensionOf(f)
	set nm to my fileName(f)
	if nm does not contain "." then return ""
	set AppleScript's text item delimiters to "."
	set ext to last text item of nm
	set AppleScript's text item delimiters to ""
	-- AppleScript compares text without case by default, so "MP3" matches.
	return ext
end extensionOf
