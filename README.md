\# PowerShell to EXE GUI



A modern WPF GUI that converts any PowerShell `.ps1` script into a standalone, natively-compiled Windows executable — no manual Rust/Cargo wrangling, and no separate dependency-install step. Created by Nazim Hassani.


<img width="705" height="553" alt="image" src="https://github.com/zimzimax/powershell_to_exe_gui/blob/main/docs/screenshot-setup.png" />
<img width="964" height="631" alt="image" src="https://github.com/zimzimax/powershell_to_exe_gui/blob/main/docs/screenshot-builder.png" />







\## Why this exists, and how it differs from ps2exe



\[ps2exe](https://github.com/MScholtes/PS2EXE) is the well-known way to turn a PowerShell script into an `.exe`, and it works by wrapping a PowerShell host inside a compiled C# launcher. It's lightweight and doesn't need a Rust toolchain — for most scripts, it's the simpler choice.



This tool takes a different approach: it generates a real Rust/Cargo project, embeds your script as a string constant at compile time (`include\_str!`), and compiles a genuine native binary that shells out to `powershell.exe` at runtime. That trade-off means a heavier one-time setup (Rust + MSVC Build Tools), but you get a real compiled wrapper, automatic GUI-vs-console detection, an in-app dependency installer so you never touch a terminal to set any of this up, and optional embedded Windows version info (Product Name, File Description, Company, Copyright) on the resulting exe.



If you just want the fastest path to an exe and don't care about any of that, use ps2exe. If you want a GUI-first experience that also handles its own prerequisites, this is built for that.



\## Features



\- \*\*Drag-and-drop or browse\*\* to pick any `.ps1` file

\- \*\*Auto-detects GUI vs console scripts\*\* (or force either mode manually)

\- \*\*Self-installing prerequisites\*\* — a Setup window checks for the Rust toolchain, MSVC Build Tools, and PowerShell 5+, and can install whatever's missing automatically (winget first, with a direct-download fallback to the official Microsoft/rust-lang installers)

\- \*\*Optional file properties\*\* — set Product Name, File Description, Version, Company Name, and Copyright, embedded into the exe's Windows version resource (visible in Explorer → Properties → Details)

\- \*\*Live build log\*\* streamed straight into the window

\- \*\*Keep or discard\*\* the generated Rust project after building

\- Self-adapting window sizing so the UI fits your screen without needing to maximize



\## Requirements



\- Windows 10 or 11

\- Windows PowerShell 5.1+ (the built-in `powershell.exe` — not PowerShell 7/`pwsh`)

\- Internet access the first time you build (to install Rust/MSVC Build Tools if missing, and to fetch crates from crates.io)

\- Administrator privileges are recommended for the first run, since installing MSVC Build Tools may require elevation



You do \*\*not\*\* need to install Rust or Visual Studio Build Tools yourself — the app's Setup window will do it for you the first time you run it.



\## Usage



```powershell

git clone https://github.com/zimzimax/powershell\_to\_exe\_gui.git

cd powershell\_to\_exe\_gui

powershell -ExecutionPolicy Bypass -File .\\ps_to_exe_gui.ps1

```



1\. On first launch, the \*\*Setup\*\* window checks for Rust, MSVC Build Tools, and your PowerShell version. If anything's missing, click \*\*Install dependencies\*\* and let it run (this can take a few minutes — it's downloading and installing a full Rust toolchain and/or Visual Studio Build Tools).

2\. Click \*\*Continue\*\* once everything shows green.

3\. In the \*\*Builder\*\* window, browse to your `.ps1` file and (optionally) an output folder.

4\. Pick build options — Auto-detect mode works for most scripts.

5\. Optionally fill in File Properties if you want custom version info on the exe.

6\. Click \*\*BUILD EXE\*\*.



The compiled executable is dropped in your chosen output folder, named after your original script.



\## How it works



For each build, the tool:



1\. Generates a temporary `cargo new --bin` project

2\. Writes a `Cargo.toml` and a `main.rs` that embeds your script via `include\_str!`

3\. If you filled in any file properties, generates a `build.rs` that uses the \[`winres`](https://crates.io/crates/winres) crate to stamp a Windows version resource onto the binary

4\. Runs `cargo build --release`

5\. Copies the resulting `.exe` to your chosen output folder (and cleans up the temp project, unless you checked "Keep Rust project")



Two `main.rs` templates exist: a console variant that streams the wrapped script's output live, and a GUI variant (`windows\_subsystem = "windows"`, launched with a hidden PowerShell window) for WPF/WinForms scripts so no console flashes on screen.



\## Security \& transparency



This tool downloads and silently runs installers when prerequisites are missing. Specifically:



\- `https://aka.ms/vs/17/release/vs\_buildtools.exe` — official Microsoft Visual Studio Build Tools bootstrapper (only if MSVC Build Tools aren't already detected)

\- `https://static.rust-lang.org/rustup/dist/x86\_64-pc-windows-msvc/rustup-init.exe` — official Rust installer (only if Rust/Cargo isn't already detected)

\- The `winres` crate from crates.io — only if you fill in any File Properties field



Where available, it tries `winget` first and only falls back to direct download if `winget` isn't present or doesn't work. As with any script that installs system components, read through `PsToExeGui.ps1` before running it on a machine you care about.



\## Known limitations



\- Windows only.

\- The first build after installing Rust can be slow (toolchain + initial crate compilation). Subsequent builds are much faster.

\- The output exe is unsigned, so Windows SmartScreen may warn on first run — this is normal for any unsigned, freshly-built executable and isn't specific to this tool.

\- Requires Windows PowerShell (`powershell.exe`), since the generated wrapper invokes it directly.



## License

MIT — see [LICENSE](LICENSE).

\## Author



Nazim Hassani



