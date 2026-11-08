on run
    set appPath to POSIX path of (path to me)
    set localPath to appPath & "Contents/Resources/apertus-local"
    tell application "Terminal"
        activate
        do script "cd " & quoted form of localPath & " && ./Start.command"
    end tell
end run
