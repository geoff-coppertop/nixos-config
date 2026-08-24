# Bambuddy (github.com/maziggy/bambuddy) — a self-hosted Bambu Lab printer
# manager: FastAPI backend serving a Vite/React SPA out of ./static.
#
# Packaged natively rather than as the upstream OCI image, because everything
# the image adds on top of the app is Docker plumbing this host does not need:
# the PUID/PGID chown + gosu entrypoint (systemd's User=/StateDirectory= does
# that), `network_mode: host` for SSDP discovery and camera streaming (a native
# unit has no netns to escape), and `setcap` on the interpreter for the
# virtual printer's privileged ports (systemd's AmbientCapabilities= instead).
# See modules/bambuddy.nix, which is this package's only consumer.
#
# Upstream ships a native-install path deliberately — backend/app/core/config.py
# reads DATA_DIR/LOG_DIR from the environment specifically "on native installs
# where DATA_DIR is set to a sibling like INSTALL_PATH/data", and install/
# install.sh generates a systemd unit. That unit is what modules/bambuddy.nix
# mirrors.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  buildNpmPackage,
  makeWrapper,
  nodejs_22,
  # Deliberately python313, not the `python3` alias — that alias is 3.14 on
  # this nixpkgs pin, and 3.13 is what upstream actually ships and tests (its
  # Dockerfile's runtime stage is python:3.13-slim-trixie). pyproject.toml
  # claims >=3.10 and backend/app/core/compat.py carries explicit 3.10
  # shims, but there is nothing in the tree acknowledging 3.14, and a runtime
  # incompatibility there would surface on the host rather than in a build.
  python313,
  ffmpeg,
}: let
  # backend/app/core/config.py's APP_VERSION, which is also the tag name.
  # (pyproject.toml's own `version = "0.1.5"` is stale upstream and is not
  # what the app reports about itself.)
  version = "1.2.5.3";

  src = fetchFromGitHub {
    owner = "maziggy";
    repo = "bambuddy";
    tag = "v${version}";
    # Real NAR hash, from CI's own hash-mismatch error on PR #142's first run
    # (https://github.com/geoff-coppertop/nixos-config/actions/runs/32638403372) —
    # no local Nix toolchain was available to compute it directly.
    hash = "sha256-IrjiHTSHeoEnpHunI/5dWUhI6HJdXI6kWX5Aoxp54EI=";
  };

  # Node 22, matching upstream's own Dockerfile builder stage.
  #
  # `sourceRoot` is frontend/, but the build output is NOT frontend/dist:
  # frontend/vite.config.ts sets `build.outDir = '../static'`, so `npm run
  # build` writes to the *repo root's* static/. That is why the whole repo is
  # the src and the install phase copies ../static — a src scoped to frontend/
  # alone would have vite writing outside its own source root.
  #
  # The repo does carry a committed static/ built by upstream's release
  # tooling, and `emptyOutDir` wipes it before this build writes its own. It is
  # deliberately not used as-is: nothing guarantees the committed artifacts
  # match the frontend sources at the same commit, and upstream's Dockerfile
  # rebuilds rather than trusting them too.
  frontend = buildNpmPackage {
    pname = "bambuddy-frontend";
    inherit version src;

    nodejs = nodejs_22;
    sourceRoot = "${src.name}/frontend";

    # Real hash, from CI's own hash-mismatch error on PR #142's second run
    # (https://github.com/geoff-coppertop/nixos-config/actions/runs/32638727838) —
    # same reason as `src.hash` above for why this wasn't computed locally.
    npmDepsHash = "sha256-6s5vAQq4/8FqihixBfYY7tUMHI9VmPOUYNEbQBPBXBs=";

    # The repo commits a pre-built ../static (upstream's own release
    # tooling), which arrives from fetchFromGitHub read-only. vite's build
    # tries to rm -rf its outDir before writing, and CI failed with EACCES:
    # permission denied, rmdir '.../static/assets' — reproduced locally
    # outside Nix by chmod -R a-w on a copy of ../static and building as an
    # unprivileged user (the Nix build user isn't root, unlike a quick local
    # check as root, which masks the permission bits entirely and builds
    # fine either way). Removing the stale committed copy ourselves sidesteps
    # vite's own rm-then-write entirely, and matches this package's existing
    # stance (see the module-level comment above) that the committed static/
    # isn't trusted to match the frontend sources at this commit anyway.
    #
    # chmod before rm, not just rm -rf: unlinking a directory entry needs
    # write permission on its *parent*, not the entry itself, so `chmod -R
    # u+w ../static` alone (round 1 of this fix) still hit "rm: cannot
    # remove '../static': Permission denied" in CI — the repo root (`..`,
    # frontend's parent) is read-only too, from the same fetchFromGitHub
    # source. chmod that as well, but only it, not the whole tree: `npm
    # ci`/npmConfigHook already leaves node_modules itself writable, and a
    # broader `chmod -R u+w ..` here would be needlessly heavy-handed.
    # Reproduced and confirmed fixed locally the same way as round 1 (a
    # copy with everything except node_modules made read-only, built as an
    # unprivileged user).
    preBuild = ''
      chmod u+w ..
      chmod -R u+w ../static
      rm -rf ../static
    '';

    # Replaces npmInstallHook entirely (the hook only installs itself when
    # installPhase is unset). This package is a directory of static assets,
    # not an npm package to be `npm pack`ed into node_modules.
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r ../static/. $out/
      runHook postInstall
    '';

    meta.description = "Built static assets for the Bambuddy web UI";
  };

  # requirements.txt at v1.2.5.3, minus tzdata (marked sys_platform ==
  # "win32") and the dev-only pytest/ruff set in requirements-dev.txt.
  #
  # Three of upstream's floors/caps are not met by this nixpkgs pin. All three
  # are pip-resolution or audit concerns, not runtime ones, and none applies to
  # a Nix build that never runs pip:
  #
  #   fastapi<0.136.0     — held back only because fastapi[standard] gained a
  #                         dependency on the `fastar` PyPI name, which
  #                         pip-audit flags. Bambuddy never requests
  #                         [standard], and nixpkgs does not install optional
  #                         dependency groups at all, so 0.139.0 is fine.
  #   pydantic-settings   — floor 2.14.2 is precautionary for
  #     >=2.14.2            GHSA-4xgf-cpjx-pc3j in NestedSecretsSettingsSource,
  #                         a source Bambuddy does not use.
  #   pyopenssl>=26.4.0   — that floor exists because each pyOpenSSL release
  #                         caps `cryptography` to a narrow window, so pip
  #                         would silently hold cryptography below its fix
  #                         line. nixpkgs already pairs pyopenssl 26.3.0 with
  #                         cryptography 50.0.0, which is the outcome the
  #                         floor was there to force.
  #
  # amqtt is deliberately absent: backend/app/services/virtual_printer/
  # mqtt_server.py imports it lazily and falls back to its own minimal broker
  # when it is missing, it is not in requirements.txt, and upstream's own
  # image therefore runs the fallback path too. It is also not in nixpkgs.
  pythonEnv = python313.withPackages (
    ps:
      (with ps; [
        aiofiles
        aioftp
        aiohttp
        aiosqlite
        asyncpg
        asyncssh
        # passlib[bcrypt]
        bcrypt
        certifi
        cryptography
        curl-cffi
        defusedxml
        fastapi
        fast-simplification
        greenlet
        httpx
        idna
        ldap3
        lxml
        matplotlib
        networkx
        numpy
        openpyxl
        # nixpkgs packages this as a metapackage over opencv4's Python
        # bindings — the same `cv2` module the PyPI wheel provides.
        opencv-python-headless
        paho-mqtt
        passlib
        pillow
        psutil
        pydantic
        pydantic-settings
        pyftpdlib
        pyjwt
        pyopenssl
        pyotp
        python-dotenv
        python-multipart
        pywebpush
        # qrcode[pil] — the extra is pillow, already listed above
        qrcode
        reportlab
        sqlalchemy
        starlette
        trimesh
        urllib3
        uvicorn
      ])
      # uvicorn[standard]. `websockets` out of this set is load-bearing —
      # the frontend talks to /api/v1/ws — while `uvloop` out of the same
      # set is deliberately bypassed at runtime by the unit's --loop asyncio
      # (see modules/bambuddy.nix for why).
      ++ ps.uvicorn.optional-dependencies.standard
  );
in
  stdenvNoCC.mkDerivation {
    pname = "bambuddy";
    inherit version src;

    nativeBuildInputs = [makeWrapper];

    dontBuild = true;

    # The layout under lib/bambuddy is load-bearing, not cosmetic:
    # backend/app/core/config.py derives the application root from
    # `Path(__file__).resolve().parent.parent.parent.parent` and reads
    # `<root>/static` from it, so backend/ and static/ must stay siblings.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/bambuddy
      cp -r backend $out/lib/bambuddy/backend
      # Not needed at runtime, and it pulls pytest fixtures into the closure.
      rm -rf $out/lib/bambuddy/backend/tests
      cp -r ${frontend} $out/lib/bambuddy/static

      # ffmpeg is resolved with shutil.which() by
      # backend/app/services/camera.py (camera stream transcoding and snapshot
      # capture), so it has to be on PATH rather than a Python dependency.
      makeWrapper ${pythonEnv}/bin/uvicorn $out/bin/bambuddy \
        --add-flags backend.app.main:app \
        --prefix PYTHONPATH : $out/lib/bambuddy \
        --prefix PATH : ${lib.makeBinPath [ffmpeg]}

      runHook postInstall
    '';

    meta = {
      description = "Self-hosted management, archive, and print queue for Bambu Lab 3D printers";
      homepage = "https://github.com/maziggy/bambuddy";
      changelog = "https://github.com/maziggy/bambuddy/blob/v${version}/CHANGELOG.md";
      license = lib.licenses.agpl3Only;
      mainProgram = "bambuddy";
      platforms = lib.platforms.linux;
    };
  }
