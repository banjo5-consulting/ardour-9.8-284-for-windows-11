# Building Ardour on Windows with MSYS2

Scripts that build the [Ardour](https://ardour.org) digital audio workstation from source on Windows, using MSYS2's MINGW64 environment.

**Read how this was built, with AI and with a person checking every step:** [Building Ardour on Windows with AI](https://banjo5.com/ardour.html) (Banjo5)

> **Unofficial.** This project isn't affiliated with or endorsed by Ardour. Ardour's developers build their Windows releases by cross-compiling on Linux and don't support native Windows builds. **Please don't ask them for help with this build**; open an issue here instead.
>
> **Support Ardour.** If you use Ardour, consider buying the official ready-made version from [ardour.org](https://ardour.org) (from US$1). It funds the people who build it.

## What you get

- Ardour installed in `C:\Ardour`, started with a double-click on `C:\Ardour\Start-Ardour.bat`
- PortAudio built with **ASIO** support (or WASAPI only, if you prefer)
- Every step logged to a file, and safe to re-run: finished steps are skipped

## Tested with

| Component | Version |
|---|---|
| Ardour | 9.8 development build (`9.8-284`), commit `704731d2a5468f6f4ca77f9130eb893dc38ec7e9` |
| PortAudio | commit `1ca0eeedb678c3cca80f3306c474d69a7a4b5278` |
| FFTW | 3.3.10, MD5 `8ccbf6a5ea78a16dbc3e1306e234cc5c` (checked by the script) |
| ASIO SDK | Steinberg release with files dated 13 October 2025, SHA-256 `d5ebf0c20dd2c5f43771fd0c1418f4b361bf52434ee670097cfa6b3a335e2eca` |
| MSYS2 | MINGW64, GCC 16.2.0 (Rev4), last full update 27 September 2026 |
| Windows | Windows 11 |

To check that your ASIO SDK download is the same file, run `sha256sum asiosdk.zip` in the MINGW64 shell and compare. A newer SDK will probably work too, but hasn't been tested.

**Tested so far:** building, launching, and recording and playing back audio through a computer's built-in microphone. **Not yet tested:** an audio interface over ASIO, and the video timeline.

The scripts pin these exact versions on purpose. Newer Ardour code may need new fixes; see [Limitations](#limitations).

## How to build

Expect 1–2 hours in total, most of it compiling.

1. **Install MSYS2** from [msys2.org](https://www.msys2.org) to `C:\msys64`.
2. **Update MSYS2.** Open **MSYS2 MINGW64** from the Start menu (not UCRT64 or MSYS) and run `pacman -Syu`. The window closes; reopen MINGW64 and run `pacman -Syu` again.
3. **Download the ASIO SDK** in a browser from Steinberg's developer site (Developers > ASIO SDK) and save it as `C:\msys64\home\<username>\ardour-build\asiosdk.zip`. The SDK is under Steinberg's license; this repository doesn't include it.
   *No ASIO needed?* Skip this step and run the build with `PA_USE_ASIO=OFF bash build-ardour-msys2.sh` to use WASAPI only.
4. **Copy both scripts** (`build-ardour-msys2.sh` and `bundle-ardour-dlls.sh`) into `C:\msys64\home\<username>\`. Keep Unix (LF) line endings if you edit them.
5. **Run the build** in the MINGW64 shell:
   ```
   bash build-ardour-msys2.sh
   ```
   The script:
   1. installs the dependencies with `pacman`
   2. builds PortAudio with ASIO, without JACK, as a static library
   3. downloads FFTW 3.3.10, checks it against the official checksum, and builds it in single precision
   4. downloads Ardour at the tested version, with no patches
   5. configures, builds and installs Ardour to `C:\Ardour`
   6. writes `C:\Ardour\Start-Ardour.bat` and runs the DLL bundling script
6. **Check the logs** if anything fails: `C:\share\log.txt` (previous run: `log.prev.txt`) and `C:\share\bundle-log.txt`. A failure names the script line that stopped it.
7. **Start Ardour** by double-clicking `C:\Ardour\Start-Ardour.bat`. It puts MSYS2's libraries first on Windows' search path, so Ardour runs with exactly the libraries it was built against. You can make a desktop shortcut to it.
8. **For scoring to picture**, add the video tools: download the Windows builds of Harvid and Xjadeo from [x42.github.io](https://x42.github.io) and set their folder in Ardour under **Edit > Preferences > Video**.

After a rebuild or an MSYS2 update, run `bash bundle-ardour-dlls.sh` again.

## Troubleshooting

These are the problems we hit while turning the [community recipe](https://discourse.ardour.org/t/building-ardour-on-windows-using-msys2/112412) into these scripts. The scripts already include every fix.

| Symptom | Cause | Fix |
|---|---|---|
| `RPC failed; curl 56 Recv failure: Connection reset by peer` or `early EOF` while getting the Ardour source | Ardour's full history is a large download, and the connection dropped | The script retries 3 times. If it still fails, check your connection and run it again; finished steps are skipped |
| PortAudio build fails at the ASIO step | Steinberg's download link needs a browser; a scripted download saves a web page instead of the zip | Download the SDK in a browser and save it as `asiosdk.zip` in the build folder (step 3) |
| `undefined reference to regcomp`, `regexec`, `regfree` when linking `libportaudio.dll` | PortAudio's JACK support needs a POSIX regex library that MSYS2 doesn't link by default | Build PortAudio with `-DPA_USE_JACK=OFF` (Ardour has its own JACK backend) and as a static library (`-DBUILD_SHARED_LIBS=OFF`), which Ardour's build expects |
| Python `IndentationError` in `libs/backends/portaudio/wscript` during configure | The forum recipe's `sed` patches are now part of Ardour's own code; applying them again adds duplicate, mis-indented lines | Don't apply the patches. If an earlier run did, restore the files with `git checkout` (the script does this) |
| *(Would have broken the compile)* | The recipe's other patches insert `#if` lines at fixed line numbers in `pbd.cc` and `main.cc`, which now land on unrelated lines | Removed along with the patches above |
| Starting the `.exe` shows "libcairo-2.dll / libcurl-4.dll / libcairomm-1.0-1.dll / libfftw3f-3.dll was not found" | The build links against DLLs in `C:\msys64\mingw64\bin`, which isn't on Windows' search path | Start Ardour with `Start-Ardour.bat`, which adds that folder to the search path. `bundle-ardour-dlls.sh` also copies the required DLLs (133 in our build) next to the `.exe` |
| Starting the `.exe` directly shows "midipp.dll is either not designed to run on Windows or contains an error" | Not fully diagnosed. Seen on the first start after a clean rebuild, even with every bundled DLL in place | Start Ardour once with `Start-Ardour.bat`. After that, the `.exe` also starts directly |
| Bundling reports "not found" DLLs such as `ardour.dll`, `pbd.dll`, `ytk.dll` | False alarm: `ldd` checks plugins in subfolders and doesn't look in the `.exe`'s folder, where these DLLs already are | The script now only warns about DLLs that exist nowhere in the install |

## Limitations

- **Unsupported by Ardour's developers.** Future Ardour changes may break this build again. To try newer code, change `ARDOUR_REF` in the script and expect to troubleshoot.
- **PortAudio and FFTW are installed into MSYS2's own folders** (`/mingw64`). Installing the same libraries later with `pacman` may conflict with them.
- **`C:\Ardour` uses copies of MSYS2's DLLs.** Updating MSYS2 doesn't update those copies; run `bundle-ardour-dlls.sh` again after an update or a rebuild.
- **The video timeline tools aren't included** (see step 8).
- **Tested on one Windows machine** (see [Tested with](#tested-with)).

## How these scripts were made

The scripts were written with AI (Claude Desktop) and read by a person before every run. The AI and the person shared one folder: each run wrote its full log there, the AI diagnosed the failure from the complete log and revised the script, and the person ran the same command again. The write-up explains the method and what we learned: [Building Ardour on Windows with AI](https://banjo5.com/ardour.html).

## License

The scripts in this repository are released under the [MIT License](LICENSE). Ardour is licensed under the GPL v2, and the ASIO SDK under Steinberg's own terms; neither is included here.
