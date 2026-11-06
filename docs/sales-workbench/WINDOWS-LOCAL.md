# Windows local browser demo

This package builds the sales workspace from this fork. It includes PostgreSQL,
FreeSWITCH, the Go backend, the Chinese workspace, and synthetic demo data.
It is a browser evaluation install, not a completed AI calling integration.
No AI credentials or carrier are configured. The AI path is explicitly disabled.
Only the web port on 127.0.0.1 is published; phone ports are not published, and
the runtime Compose network is internal. Live speech and Windows phone media
have not been validated by this launcher.

## Start

1. Extract the entire ZIP into a permanent folder, for example `C:\AICC-Sales`.
   Do not run a launcher from inside the ZIP. Do not copy only the launchers.
2. Double-click `Start-Local.cmd`.
3. If Docker Desktop is missing, the launcher downloads its official signed
   Windows installer and opens it. Complete its dialogs. If Windows requests a
   restart, restart and run `Start-Local.cmd` again. Complete Docker Desktop's
   first-run dialogs; the launcher does not accept license terms on your behalf.
4. Keep the terminal open during image downloads and the source build.
5. After an actual administrator login and page request pass, the launcher
   displays the local address, username `admin`, and generated password, and
   opens the browser. No success message is printed before those checks pass.

Requirements: supported 64-bit Windows, WSL2/hardware virtualization, Docker
Desktop with Linux containers, Compose >=2.24.4, enough free disk for images and
build caches, and internet access for GitHub, Docker registries, npm and Go
dependencies. Docker's current Windows requirements are authoritative:
https://docs.docker.com/desktop/setup/install/windows-install/
WSL setup: https://learn.microsoft.com/windows/wsl/install

No Git, Node, Go, PostgreSQL or FreeSWITCH host installation is necessary.
Those build tools and services run in containers. On a restricted network,
image/dependency downloads can still fail; the package does not bypass that.

## Stop and restart

Double-click `Stop-Local.cmd` to stop services while preserving data. Double-click
`Start-Local.cmd` again to resume. Keep the extracted folder: configuration and
credentials live in `deploy/.env.windows-local`, database data in Docker volumes.
The existing `deploy/.env` and other Compose projects are left unchanged.
The project name is `aicc-sales-local`, with its own image, network and volumes.

The launcher changes execution policy only for its child PowerShell process.
Its generated credential file is restricted to the Windows account and SYSTEM.
Passwords are shown only in the local terminal; do not paste them into chat.

For a different web port on the first installation, run from the extracted folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-local.ps1 -Port 18080
```

The selected port is retained on later runs. If 8080 is already occupied after
configuration was generated, stop this project, change `AICC_LOCAL_HTTP_PORT` in
`deploy/.env.windows-local`, then start again. Do not delete or regenerate
passwords to resolve a port conflict: existing seeded accounts keep their password.

## Failure diagnostics

Docker installation can require OS dialogs, elevation, enabling virtualization,
or a restart. This package cannot click these dialogs or change firmware settings.
If Docker does not become ready, open its window and resolve the shown problem.
If the build fails, retain the first failing command and its error. Do not delete
the folder or database volumes. Container logs are available in Docker Desktop,
under `Containers > aicc-sales-local`.

Runtime verification in this launcher covers administrator login, the health API
and the served HTML. Inspect the container list as well. It does not certify SIP
audio, real model responses, a carrier, or customer calls. No full Windows end to
end test was run in the Linux packaging environment.

Real calling remains a separate integration of approved phone lines, AI keys,
authorization controls and a controlled test. Do not add real customer data during
this evaluation.
