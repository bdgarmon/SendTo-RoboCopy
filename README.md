Why Use This?
-------------------------------
Windows File Explorer uses the legacy CopyFileEx API for drag-and-drop. That path is single-threaded, uses small buffered I/O, and adds shell overhead like thumbnailing and content indexing. Over SMB to a NAS, this results in many small round-trips and CPU time spent on buffering rather than saturating the link. In contrast, Robocopy can run multiple parallel copy threads, perform large unbuffered reads/writes, resume partially-copied files, and avoid Explorer’s extra processing. The scripts in this toolkit wrap Robocopy to give you a clear progress bar, automatic stall handling, and per-run logs, while the right‑click integration lets you launch fast copies directly from Explorer without manual command lines.

What this kit contains
----------------------
1) Start-RoboCopyWithProgress.ps1 – A Windows Powershell 7.x progress wrapper with Int64 math, per-run logging, and stall detection (exits if no new bytes for N seconds; optional auto-kill).
2) FastCopy.ps1 – “Send To” helper that prompts for a destination, then runs Robocopy with sensible defaults for speed and reliability. It remembers your last destination unless you force a prompt.
3) Install-FastCopyContext.ps1 – installer that creates two Explorer Send-To shortcuts: a regular one that prompts every run and a DEBUG one that keeps the console open. Optionally adds a folder‑background “Fast Paste here (Robocopy)” entry.
4) Registry files (optional) to enable (or undo) the classic Windows 10-style right‑click menu so “Send to” is immediately visible.

Technical advantages
---------------------------------------
• Multi-threaded copy (/MT) increases throughput by transferring multiple files or chunks in parallel. One thread often leaves bandwidth idle; several threads can fill a 10Gb link when the storage can keep up.  
• Unbuffered I/O (/J) avoids double-buffering through the OS cache on huge files. This reduces CPU usage and cache thrash, letting SMB and disks run closer to line rate. For many tiny files, omit /J.  
• Lightweight logging and no Explorer UI work mean fewer context switches. You get consistent, scriptable behavior, clean ETA, and resumability without Explorer’s slowdowns.  
• Long-path friendliness (use \\?\ prefixes when needed) prevents stalls from deep folder trees (e.g., BDMV structures).  
• The wrapper adds progress that reflects actual bytes landing at the destination and bails out if a job “sticks” after completion tasks like timestamping or AV scans.

Prerequisites
-------------
• PowerShell 7.0+ (tested on 7.5.3).  
• Robocopy (built into Windows).  
• Write access to the NAS share. If the NAS requires credentials, map them first with either New‑PSDrive -Credential -Persist or cmdkey /add:<NAS_IP> /user:<DOMAIN\user> /pass:<password>.

Installation (one-time)
-----------------------
1) Place FastCopy.ps1 and Install-FastCopyContext.ps1 in a folder you control (e.g., C:\Users\<you>\Scripts or C:\Scripts). Keep Start-RoboCopyWithProgress.ps1 in your script folder too if you want the progress wrapper.  
2) Open PowerShell 7 as your user. Temporarily allow script execution in this session:  
   Set-ExecutionPolicy Bypass -Scope Process -Force  
3) Run the installer to create both right‑click entries:  
   .\Install-FastCopyContext.ps1  
   Optional: add a background “paste here” menu (destination-driven):  
   .\Install-FastCopyContext.ps1 -AddBackgroundMenu  
4) (Optional but recommended) Enable the classic context menu so “Send to” is first‑level: import Enable_Classic_Context_Menu_Win11.reg, then restart Explorer (Stop-Process -Name explorer -Force). Use the provided “Restore” REG to undo later.

Daily Usage
-----------
• Source-driven (most common): select one or more files/folders, right-click → Send to → “Fast Copy (Robocopy)”. You will be prompted for a destination each time. The DEBUG variant keeps the console open for live messages.  
• Destination-driven (optional): navigate into the target folder, right-click empty space → “Fast Paste here (Robocopy)”, then choose sources in the file picker dialog. This is useful when you are dropping multiple small items into a single destination repeatedly.  
• The helper logs every run under %USERPROFILE%\Documents\FastCopyLogs. Each run has a transcript (FastCopy_*.log) and a Robocopy log (Robocopy_*.log). If a window flashes and closes, check these logs.

Recommended settings and tips
-----------------------------
• For huge single files (e.g., MKV/ISO): use /MT:32 and /J for maximum throughput. Consider /R:1 /W:1 to avoid long retries.  
• For folders with many small files: keep /MT (e.g., 8–16) but omit /J to reduce per-file overhead. You can add /XJ to skip junctions and /XF Thumbs.db *.tmp desktop.ini to avoid lock-prone files.  
• If a job seems to “hang” near 100%, it’s usually finishing timestamps/attributes or being scanned by AV. The v4.2 wrapper will exit after StallSeconds of no byte growth; simply re-run the same job and Robocopy will skip completed files.  
• If you hit “file in use” (ERROR 32), re-run later or copy everything except that file (/XF <filename>) and transfer the locked file by itself once released. Resource Monitor or Process Explorer can identify the locking process.  
• Long or deep paths: use \\?\C:\... and \\?\UNC\<server>\<share> prefixes. Add /FFT when copying to NAS to tolerate 2‑second timestamp granularity.  
• Parallel jobs: it is fine to run a couple of jobs at once if they target different NAS hosts or different disks. For best overall speed, avoid running multiple large jobs to the same destination at the same time.

Using the progress wrapper (optional)
-------------------------------------
• Single file example (fast, unbuffered):  
  .\Start-RoboCopyWithProgress_v4_2.ps1 -Source "C:\Videos\movie.mkv" -Destination "\\NAS\Share\Movies" -Threads 32 -Unbuffered  
• Folder example (mixed files, safer closeout):  
  .\Start-RoboCopyWithProgress_v4_2.ps1 -Source "C:\SEEDS\RAMPAGE" -Destination "\\NAS\Media\RAMPAGE" -IncludeSubdirs -Threads 16 -StallSeconds 15  
The wrapper shows overall % complete, smoothed MB/s, ETA, and writes per-run logs to .\Logs\<timestamp>\

Right-click installer details
-----------------------------
• “Fast Copy (Robocopy)” – prompts for a destination every run (-ForcePrompt), copies selected items, preserves names, uses /MT and optional /J.  
• “Fast Copy (DEBUG)” – same as above but keeps the console open (-NoExit) for live diagnostics.  
• “Fast Paste here (Robocopy)” (optional) – appears on empty space inside folders and uses that folder as the destination (you then pick sources).  
• The helper remembers your last destination (HKCU\Software\FastCopy\LastTarget). Clear that value or use -ForcePrompt to ensure a prompt every time.

Troubleshooting
---------------
• Immediate exit with skip: Robocopy found the same file already present; add /IS /IT to force overwrite or delete the destination file first.  
• ERROR 32 (file in use): a process is holding the file open. Pause media indexers, Plex/Emby, or Antivirus, or copy around the file with /XF and transfer it later.  
• Permissions/credentials: if writes fail, re-authenticate to the NAS (net use \\<NAS>\<share> /delete; then cmdkey /add:<NAS> /user:<user> /pass:<pass>).  
• Verify integrity: compare sizes or run Get-FileHash on source and destination.  
• Logs: check %USERPROFILE%\Documents\FastCopyLogs for the transcript and Robocopy output; for the progress wrapper, see .\Logs\<timestamp>\ inside your script folder.

Uninstall
---------
• Remove Send-To shortcuts from %APPDATA%\Microsoft\Windows\SendTo (Fast Copy *.lnk).  
• If added, remove the background menu key HKCU\Software\Classes\Directory\Background\shell\FastPasteRobocopy.  
• To restore the modern right‑click menu, import Restore_Win11_Modern_Context_Menu.reg and restart Explorer.

Notes
-----
This kit prioritizes speed and operator control. It does not replace Explorer’s drag‑and‑drop engine; it gives you a faster path for SMB copies with clear progress and logs. Use one large job at a time for maximum throughput to the same NAS, and overlap only when you are targeting different storage paths or hosts.
