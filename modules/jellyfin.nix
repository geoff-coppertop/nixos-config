{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.jellyfin;
  os = cfg.openSubtitles;
  inherit (cfg) lapse;

  # Runs before every Jellyfin start, as the service user. Jellyfin keeps all of
  # this as files under its data dir (plugin folders, the plugin's XML config,
  # each library's options.xml), so there is no API to call -- but it only reads
  # them at startup, which is why this is an ExecStartPre. Each step is
  # independent and failure-tolerant: a missing secret must not stop the media
  # server from starting.
  setup = pkgs.writeScript "jellyfin-plugins-setup" ''
    #!${pkgs.python3}/bin/python3
    import hashlib
    import json
    import os
    import shutil
    import stat
    import sys
    import uuid
    import xml.etree.ElementTree as ET

    conf = json.load(open(sys.argv[1]))
    data = conf["dataDir"]
    plugins = os.path.join(data, "plugins")


    def write_xml(tree, path, mode):
        tmp = path + ".tmp"
        tree.write(tmp, encoding="utf-8", xml_declaration=True)
        os.chmod(tmp, mode)
        os.replace(tmp, path)


    def install_plugins():
        os.makedirs(plugins, exist_ok=True)
        for plugin in conf["plugins"]:
            for entry in os.listdir(plugins):
                if entry.startswith(plugin["name"] + "_"):
                    shutil.rmtree(os.path.join(plugins, entry))
            dest = os.path.join(plugins, plugin["dir"])
            shutil.copytree(plugin["package"], dest)
            for root, dirs, files in os.walk(dest):
                for d in dirs:
                    os.chmod(os.path.join(root, d), 0o755)
                for f in files:
                    os.chmod(os.path.join(root, f), 0o644)
            os.chmod(dest, 0o755)


    def write_credentials():
        creds = {}
        with open(conf["openSubtitles"]["credentialsFile"]) as f:
            for line in f.read().splitlines():
                key, sep, value = line.partition("=")
                if sep:
                    creds[key] = value
        root = ET.Element("PluginConfiguration")
        ET.SubElement(root, "Username").text = creds["username"]
        ET.SubElement(root, "Password").text = creds["password"]
        ET.SubElement(root, "CredentialsInvalid").text = "false"
        configs = os.path.join(plugins, "configurations")
        os.makedirs(configs, exist_ok=True)
        write_xml(
            ET.ElementTree(root),
            os.path.join(configs, "Jellyfin.Plugin.OpenSubtitles.xml"),
            0o600,
        )


    def patch_libraries():
        base = os.path.join(data, "root", "default")
        if not os.path.isdir(base):
            return
        flags = (
            "SkipSubtitlesIfEmbeddedSubtitlesPresent",
            "SkipSubtitlesIfAudioTrackMatches",
            "RequirePerfectSubtitleMatch",
        )
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name, "options.xml")
            if not os.path.isfile(path):
                continue
            tree = ET.parse(path)
            root = tree.getroot()
            for tag in ("SubtitleDownloadLanguages",) + flags:
                for old in root.findall(tag):
                    root.remove(old)
            langs = ET.SubElement(root, "SubtitleDownloadLanguages")
            for lang in conf["openSubtitles"]["languages"]:
                ET.SubElement(langs, "string").text = lang
            for tag in flags:
                ET.SubElement(root, tag).text = "false"
            write_xml(tree, path, stat.S_IMODE(os.stat(path).st_mode))


    def write_lapse_config():
        # Only the keys we own are set; the rest of the file (webhook token,
        # sync history, ...) is the plugin's and is left as it wrote it.
        path = os.path.join(plugins, "configurations", "Jellyfin.Plugin.Lapse.xml")
        if os.path.isfile(path):
            tree = ET.parse(path)
            root = tree.getroot()
        else:
            root = ET.Element("PluginConfiguration")
            tree = ET.ElementTree(root)
        for tag, value in (
            ("DefaultEngineId", "alass"),
            ("AutoUpdateEngines", "false"),
            ("OutputMode", "OverwriteWithBackup"),
        ):
            for old in root.findall(tag):
                root.remove(old)
            ET.SubElement(root, tag).text = value
        engines = root.find("Engines")
        if engines is None:
            engines = ET.SubElement(root, "Engines")
        for old in engines.findall("EngineSettings"):
            if old.findtext("EngineId") == "alass":
                engines.remove(old)
        engine = ET.SubElement(engines, "EngineSettings")
        ET.SubElement(engine, "EngineId").text = "alass"
        ET.SubElement(engine, "PathOverride").text = conf["lapse"]["alass"]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_xml(tree, path, 0o600)


    def write_lapse_trigger():
        # Jellyfin keeps a task's triggers in <configDir>/ScheduledTasks/<id>.js,
        # where id is the MD5 of the task's class name read as a .NET Guid.
        task = "Jellyfin.Plugin.Lapse.Tasks.LibrarySyncTask"
        guid = uuid.UUID(bytes_le=hashlib.md5(task.encode("utf-16-le")).digest())
        hours, minutes = conf["lapse"]["syncTime"].split(":")
        ticks = (int(hours) * 3600 + int(minutes) * 60) * 10_000_000
        folder = os.path.join(conf["configDir"], "ScheduledTasks")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"{guid}.js"), "w") as f:
            json.dump([{"Type": "DailyTrigger", "TimeOfDayTicks": ticks}], f)


    steps = [install_plugins]
    if conf["openSubtitles"]:
        steps += [write_credentials, patch_libraries]
    if conf["lapse"]:
        steps += [write_lapse_config, write_lapse_trigger]
    for step in steps:
        try:
            step()
        except Exception as e:
            print(f"jellyfin-plugins: {step.__name__} failed: {e!r}", file=sys.stderr)
  '';

  mkPlugin = name: package: {
    inherit name;
    package = toString package;
    dir = "${name}_${package.version}";
  };

  setupConfig = pkgs.writeText "jellyfin-plugins.json" (builtins.toJSON {
    inherit (config.services.jellyfin) dataDir configDir;
    lapse =
      if lapse.enable
      then {
        alass = "${lapse.alass}/bin/alass";
        inherit (lapse) syncTime;
      }
      else null;
    plugins =
      lib.optional os.enable (mkPlugin "Open Subtitles" os.package)
      ++ lib.optional lapse.enable (mkPlugin "LAPSE" lapse.package);
    openSubtitles =
      if os.enable
      then {inherit (os) languages credentialsFile;}
      else null;
  });
in {
  options.custom.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open Jellyfin's ports in the firewall. Set false when a reverse proxy (local or cross-host) fronts it instead.";
    };

    openSubtitles = {
      enable = mkEnableOption "Jellyfin's OpenSubtitles plugin, installed and configured declaratively, downloading missing subtitles for every library";

      package = mkOption {
        type = types.package;
        description = "The plugin as a directory holding its DLL and meta.json, with a `version` attribute (a build from a Jellyfin plugin repository whose targetAbi is at or below the server's version).";
      };

      credentialsFile = mkOption {
        type = types.str;
        description = "Path to a file with `username=` and `password=` lines (an opensubtitles.com account; same shape as a CIFS credentials file). Must be readable by the jellyfin user, e.g. an agenix secret with `owner = \"jellyfin\"`.";
      };

      languages = mkOption {
        type = types.listOf types.str;
        default = ["eng" "fra"];
        description = "Languages to download subtitles in, as the ISO 639-2 codes Jellyfin itself stores (`fra`, not `fre`).";
      };
    };

    lapse = {
      enable = mkEnableOption "Jellyfin's LAPSE subtitle-sync plugin, installed declaratively";

      package = mkOption {
        type = types.package;
        description = "The plugin as a directory holding its DLL, with a `version` attribute (a build from its plugin repository whose targetAbi is at or below the server's version).";
      };

      alass = mkOption {
        type = types.package;
        description = "Package providing `bin/alass`, the engine LAPSE runs. It is the default engine, its path is written into LAPSE's settings, and LAPSE's own engine downloads are turned off.";
      };

      syncTime = mkOption {
        type = types.strMatching "[0-2][0-9]:[0-5][0-9]";
        default = "05:00";
        description = "Local time (HH:MM) of the daily run of LAPSE's \"Sync subtitles\" task, which retimes every subtitle in every library and replaces the file, keeping a `.bak`. Set after the OpenSubtitles download task so new downloads are picked up the same day. Rewritten on every start, so a schedule edited in Jellyfin's dashboard does not stick.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.jellyfin = {
        enable = true;
        inherit (cfg) openFirewall;
      };

      # Render nodes for hardware-accelerated transcoding. GPU-specific VAAPI
      # drivers (e.g. intel-media-driver) belong in the host's hardware config.
      hardware.graphics.enable = true;
    }

    # Jellyfin's per-library defaults would find nothing here: a perfect match
    # means the subtitle's file hash must equal ours, which a re-encoded rip
    # never does, and "skip if the audio track matches" would drop French
    # subtitles on any title that also carries French audio. Both are turned
    # off in every library's options.xml (the plugin itself only needs the
    # credentials).
    (mkIf (os.enable || lapse.enable) {
      systemd.services.jellyfin.serviceConfig.ExecStartPre = ["-${setup} ${setupConfig}"];
    })

    # Self-register a Traefik route when this host itself runs Traefik.
    # Jellyfin has its own accounts, so no auth middleware is added here.
    # When a different host proxies it cross-host instead, that host defines
    # the route by hand (see docs/homelab-network.md § Second DNS Instance).
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "jellyfin";
        port = 8096;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
