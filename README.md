# Building Ardour on Windows with MSYS2

Scripts that build the [Ardour](https://ardour.org) digital audio workstation (version 9.10) from source on Windows, using MSYS2's **UCRT64** environment.

**Read how this was built, with AI and with a person checking every step:** [Building Ardour on Windows with AI](https://banjo5.com/ardour.html) (Banjo5)

> **Unofficial.** This project isn't affiliated with or endorsed by Ardour. Ardour's developers build their Windows releases by cross-compiling on Linux and don't support native Windows builds. **Please don't ask them for help with this build**; open an issue here instead.
>
> **Support Ardour.** If you use Ardour, consider buying the official ready-made version from [ardour.org](https://ardour.org) (from US$1). It funds the people who build it.

## What you get

- Ardour 9.10 installed in `C:\Ardour`, started with a double-click on `C:\Ardour\Start-Ardour.bat`
- PortAudio built with **ASIO** (the build stops if ASIO is missing), or WASAPI only if you prefer
- The video timeline set up for scoring to picture: harvid, ffmpeg and xjadeo installed in `C:\Ardour\video` and registered so Ardour finds them
- Every step logged to a file, and safe to re-run: finished steps are skipped, and an interrupted compile resumes where it stopped

## Tested with

| Component | Version |
|---|---|
| Ardour | 9.10 release, git tag `9.10` (commit `820eaaa7f53daab5c4e48831018dc4bbd6ff625c`) |
| MSYS2 | UCRT64 environment; GCC 16.2.0 (`mingw-w64-ucrt-x86_64-gcc 16.2.0-6`), Boost 1.92.0, glibmm 2.66.10, lilv 0.28.0; updated 11 November 2026 |
| PortAudio | commit `1ca0eeedb678c3cca80f3306c474d69a7a4b5278`, static, ASIO on, JACK off |
| ASIO SDK | MSYS2 package `mingw-w64-ucrt-x86_64-asiosdk 2.3.4-1` (its source zip has SHA-256 `d5ebf0c20dd2c5f43771fd0c1418f4b361bf52434ee670097cfa6b3a335e2eca`) |
| FFTW | 3.3.10, MD5 `8ccbf6a5ea78a16dbc3e1306e234cc5c` (checked by the script) |
| harvid | 0.9.1 (x42 Windows installer, `C:\Program Files\harvid`), with its bundled ffmpeg/ffprobe 5.0 |
| xjadeo | 0.8.15 (x42 Windows installer, `C:\Program Files\xjadeo`) |
| Windows | Windows 11 |

**Tested so far:** building, launching, recording through an external audio interface over ASIO, and the video timeline with picture in a new session. **Not yet tested:** other PCs and audio interfaces.

The scripts pin these exact versions on purpose. Newer Ardour code may need new fixes; see [Limitations](#limitations).

## How to build

Expect 1–2 hours in total, most of it compiling (about an hour on the test PC, roughly 40 minutes of it compiling Ardour). If the PC sleeps or loses power, the compile pauses; run the script again to continue.

### Before you start

- **Install harvid and xjadeo** for Windows from [x42.github.io](https://x42.github.io). The installers put them in `C:\Program Files\harvid` and `C:\Program Files\xjadeo`; harvid includes ffmpeg. Any other location works with `HARVID_DIR`, `XJADEO_DIR` and `FFMPEG_DIR` (see [Running the helpers on their own](#running-the-helpers-on-their-own)).
- **Close** Ardour, harvid and xjadeo, and any Explorer window showing `C:\Ardour`.
- **Keep sessions and video files outside `C:\Ardour`.** It is replaced on every rebuild.

### Steps

1. **Install MSYS2** from [msys2.org](https://www.msys2.org) to `C:\msys64`.
2. **Open "MSYS2 UCRT64"** from the Start menu (not MINGW64, not MSYS) and run `pacman -Syu`. If the window closes, reopen UCRT64 and run it again until nothing is left to update.
3. **Copy the three scripts** (`build-ardour-msys2.sh`, `setup-ardour-video.sh` and `bundle-ardour-dlls.sh`) into `C:\msys64\home\<username>\`. Keep Unix (LF) line endings if you edit them.
4. **Run the build** in the UCRT64 shell:
   ```
   cd ~
   bash build-ardour-msys2.sh
   ```
   The script:
   1. installs the dependencies with `pacman`, including the ASIO SDK (no browser download needed)
   2. builds PortAudio (static, ASIO on, JACK off) and stops if ASIO isn't in it
   3. downloads FFTW 3.3.10, checks it against the official checksum, and builds it in single precision
   4. gets Ardour 9.10 with git, and does a clean build whenever the version changes
   5. configures, compiles and installs Ardour to `C:\Ardour`, moving any previous install to `C:\Ardour.prev`
   6. writes `C:\Ardour\Start-Ardour.bat`, copies the needed DLLs next to the `.exe`, and sets up the video tools

   **Accept the Windows administrator prompt** near the end. It registers the video tools so Ardour finds them.
5. **Check the logs** if anything fails: `C:\share\log.txt` (previous run: `log.prev.txt`), `C:\share\bundle-log.txt` and `C:\share\video-log.txt`. A failure names the script line that stopped it. Fix the cause and run the same command again; finished steps are skipped and the compile resumes.
6. **Start Ardour** with `C:\Ardour\Start-Ardour.bat`, or the `ardour-9.10.0.exe` it names. You can make a desktop shortcut to either.
7. **First video use:** if **Edit > Preferences > Video > Advanced Setup** is ticked (for example, settings carried over from an older Ardour), untick it. Then use **Session > Open Video**, tick **transcode** (for frame-accurate seeking), and open **View > Video Monitor**. Set the session's timecode rate to match the film.

### Running the helpers on their own

In the UCRT64 shell, from `~`:

```
bash setup-ardour-video.sh       # after installing or updating harvid / xjadeo / ffmpeg
bash bundle-ardour-dlls.sh       # after pacman -Syu, if you start the .exe directly
PA_USE_ASIO=OFF bash build-ardour-msys2.sh                                          # WASAPI only, no ASIO
ARDOUR_TARBALL=/c/Users/<you>/Downloads/Ardour-9.10.0.tar.bz2 bash build-ardour-msys2.sh   # official source tarball instead of git
HARVID_DIR="C:\Tools\harvid" XJADEO_DIR="C:\Tools\xjadeo" FFMPEG_DIR="C:\ffmpeg\bin" bash setup-ardour-video.sh
```

To build a later Ardour, change `ARDOUR_REF="${ARDOUR_REF:-9.10}"` in the build script and expect to troubleshoot.

## Troubleshooting

These are the problems we hit while turning the [community recipe](https://discourse.ardour.org/t/building-ardour-on-windows-using-msys2/112412) into these scripts, first for Ardour 9.8 and then for 9.10. The scripts already include every fix.

| Symptom | Cause | Fix |
|---|---|---|
| pacman: `target not found: mingw-w64-x86_64-glibmm` (also lilv, rubberband, aubio…) | MSYS2 no longer builds these libraries for MINGW64 | Use the MSYS2 UCRT64 shell (the script requires it) |
| "Run this from the 'MSYS2 UCRT64' shell" | Script started from MINGW64 or MSYS | Open MSYS2 UCRT64 from the Start menu |
| `RPC failed; curl 56 Recv failure: Connection reset by peer` or `early EOF` while getting the Ardour source | Ardour's full history is a large download, and the connection dropped | The script retries 3 times. If it still fails, check your connection and run it again; finished steps are skipped |
| "PortAudio was built without ASIO" | PortAudio's CMake didn't find the ASIO SDK. (In the 9.8 version of these scripts this happened silently: the SDK was unpacked into a folder CMake doesn't search, so that build very likely had no ASIO) | Check the CMake output above the error; or build WASAPI-only with `PA_USE_ASIO=OFF` |
| `undefined reference to regcomp`, `regexec`, `regfree` when linking `libportaudio.dll` | PortAudio's JACK support needs a POSIX regex library that MSYS2 doesn't link by default | Build PortAudio with `-DPA_USE_JACK=OFF` (Ardour has its own JACK backend) and as a static library (`-DBUILD_SHARED_LIBS=OFF`), which Ardour's build expects |
| Python `IndentationError` in `libs/backends/portaudio/wscript` during configure | The forum recipe's `sed` patches are now part of Ardour's own code; applying them again adds duplicate, mis-indented lines | Don't apply the patches. If an earlier run did, restore the files with `git checkout` (the script does this) |
| *(Would have broken the compile)* | The recipe's other patches insert `#if` lines at fixed line numbers in `pbd.cc` and `main.cc`, which now land on unrelated lines | Removed along with the patches above |
| "This tarball has no version info" | A GitHub "Download ZIP" was used as the source; Ardour gets its version from git | Leave `ARDOUR_TARBALL` unset; the script uses git |
| Starting the `.exe` shows "libcairo-2.dll / libcurl-4.dll / … was not found" | The build links against DLLs in `C:\msys64\ucrt64\bin`, which isn't on Windows' search path | Start Ardour with `Start-Ardour.bat`, which adds that folder to the search path. `bundle-ardour-dlls.sh` also copies the required DLLs (134 in our build) next to the `.exe` |
| Starting the `.exe` directly shows "midipp.dll is either not designed to run on Windows or contains an error" | Seen on Ardour 9.8 only, not on 9.10. Not fully diagnosed | Start Ardour once with `Start-Ardour.bat`. After that, the `.exe` also starts directly |
| Bundling reports "not found" DLLs such as `ardour.dll`, `pbd.dll`, `ytk.dll` | False alarm: `ldd` checks plugins in subfolders and doesn't look in the `.exe`'s folder, where these DLLs already are | The script only warns about DLLs that exist nowhere in the install |
| Bundling warns about `api-ms-win-crt-*.dll` | Windows' own C runtime (older versions of the script) | Ignore; it's part of Windows 10/11 |
| Video setup: "harvid.exe not found" (or xjadeo / ffmpeg) | Installed in an unusual folder | `HARVID_DIR` / `XJADEO_DIR` / `FFMPEG_DIR="C:\folder" bash setup-ardour-video.sh` |
| Video setup: "Couldn't write the registry entry" | The administrator prompt was declined or blocked | Double-click `C:\Ardour\video\register-video-tools.reg` and accept |
| "Launch Video Server" dialog reappears after Execute | **Advanced Setup** is on, with a docroot folder that no longer exists (for example, one inside the old `C:\Ardour`) | Untick **Edit > Preferences > Video > Advanced Setup** |
| Video monitor shows timecode but no picture in an old session | The session points to video files that moved (for example, inside `C:\Ardour`) | Re-import the video, or start a new session; keep media outside `C:\Ardour` |
| Video import fails when transcoding | ffmpeg is missing from Ardour's video folder, or lacks the mjpeg encoder | Re-run `setup-ardour-video.sh`; it checks both |

## Limitations

- **Unsupported by Ardour's developers.** Future Ardour changes, or changes to MSYS2's packages, may break this build again. To try newer code, change `ARDOUR_REF` in the script and expect to troubleshoot.
- **PortAudio and FFTW are installed into MSYS2's own folders** (`/ucrt64`). Installing the same libraries later with `pacman` may conflict with them; the script rebuilds PortAudio on every run for this reason.
- **`C:\Ardour` uses copies of MSYS2's DLLs.** Updating MSYS2 doesn't update those copies; run `bundle-ardour-dlls.sh` again after an update or a rebuild.
- **`C:\Ardour` is replaced on every rebuild** (the previous copy is kept in `C:\Ardour.prev`). Keep sessions and media elsewhere.
- **The video setup writes one registry value:** `HKLM\Software\Ardour\v9\video\Install_Dir`. An official Ardour 9 install, if you have one, uses the same value.
- **Tested on one Windows machine** (see [Tested with](#tested-with)).

## How these scripts were made

The scripts were written with AI (Claude Desktop) and read by a person before every run. The AI and the person shared one folder: each run wrote its full log there, the AI diagnosed the failure from the complete log and revised the script, and the person ran the same command again. The write-up explains the method and what we learned: [Building Ardour on Windows with AI](https://banjo5.com/ardour.html).

Updated for 9.10 in November 2026 the same way.

## License

The scripts in this repository are released under the [MIT License](LICENSE). Ardour is licensed under the GPL v2, and the ASIO SDK under Steinberg's own terms; neither is included here.
