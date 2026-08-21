Silent installer lifecycle (run on Windows after ISCC build):

1. `/VERYSILENT` install to `%LOCALAPPDATA%\Programs\ChaoxingTodo`
2. Register autostart `"chaoxing_windows.exe" --hidden`
3. Start `--hidden` and assert no main window
4. Upgrade must taskkill the running process
5. Uninstall must taskkill, remove the Run key, and delete the install directory
