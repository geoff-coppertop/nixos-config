{pkgs}:
# Plymouth boot theme: Framework's animated ASCII-art penguin throbber, with a
# LUKS password-entry UI (lock icon, entry box, bullet masking, caps-lock
# indicator) layered on top of the stock bgrt theme's assets.
#
# Framework-laptop-specific, so this lives under hosts/enterprise-d/ rather
# than a shared profile — see docs/architecture.md § Placement Rule.
#
# Upstream ships no NixOS packaging, just "copy the theme dir into
# /usr/share/plymouth/themes/ and run plymouth-set-default-theme -R"; this
# derivation does the equivalent of that copy into $out so it can be listed in
# boot.plymouth.themePackages. Only the files framework-penguin.script
# actually loads are installed — upstream's README.md, penguin-anim.gif, and
# two unused assets (keyboard.png, keymap-render.png) are left out.
pkgs.stdenv.mkDerivation rec {
  pname = "framework-penguin-plymouth";
  version = "unstable-2026-08-17";

  src = pkgs.fetchFromGitHub {
    owner = "ygurin";
    repo = "framework-penguin";
    rev = "49dea6aea162fb0b75d4be2668d5087557755e0c";
    hash = "sha256-UDPKNntpqKqWwGjby1yi2opeEaqPKDiB2FksPy0BXhA=";
  };

  # Upstream's watermark.png is a hardcoded Fedora wordmark, explicitly
  # meant to be swapped ("Customizable distro logo") — this is that swap,
  # for the official NixOS wordmark (icon + text, not just the snowflake
  # alone) at nixos-artwork's canonical logo/nixos.svg path.
  nixosLogo = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/master/logo/nixos.svg";
    hash = "sha256-CkPSSxq//epZGbVe/q/0UknmfXLbo0nJ7D0U1rc09o0=";
  };

  nativeBuildInputs = [pkgs.librsvg];

  dontBuild = true;

  installPhase = let
    throbberFrames = builtins.genList (i: "throbber-${pkgs.lib.fixedWidthNumber 4 i}.png") 101;
  in ''
    runHook preInstall

    themeDir=$out/share/plymouth/themes/framework-penguin
    mkdir -p "$themeDir"

    cp framework-penguin.plymouth framework-penguin.script "$themeDir/"
    cp lock.png entry.png bullet.png capslock.png "$themeDir/"
    cp ${pkgs.lib.concatStringsSep " " throbberFrames} "$themeDir/"

    # NixOS wordmark in place of upstream's Fedora watermark.png. The script
    # only ever calls Image("watermark.png").GetWidth()/GetHeight() to
    # position it — no hardcoded dimensions — so matching the original
    # 149x43 footprint (by width, aspect-preserved) is enough; no distortion
    # needed.
    rsvg-convert --width=149 "$nixosLogo" -o "$themeDir/watermark.png"

    # Upstream's .plymouth hardcodes /usr/share/plymouth/themes/framework-penguin
    # (ImageDir and ScriptFile) for a traditional FHS install — that path
    # doesn't exist on NixOS, so plymouthd fails to find the script and
    # renders nothing. Point both at the real store path instead, matching
    # how nixpkgs' own themes are packaged; NixOS's own plymouth module then
    # relocates *that* into /etc/plymouth/themes for both the root fs and
    # the initrd, the same as it does for any other store-path reference.
    substituteInPlace "$themeDir/framework-penguin.plymouth" \
      --replace-fail "/usr/share/plymouth/themes/framework-penguin" "$themeDir"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Plymouth boot theme with Framework's animated ASCII penguin and a LUKS password-entry UI";
    homepage = "https://github.com/ygurin/framework-penguin";
    license = licenses.unfree; # upstream ships no LICENSE file
    platforms = platforms.linux;
  };
}
