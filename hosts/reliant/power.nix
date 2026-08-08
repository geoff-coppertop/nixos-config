# Headless mini PC, meant to run unattended 24/7 as a homelab server (it will
# eventually replace defiant) — no lid, no display, and hibernate is neither
# needed nor useful here. NixOS's own logind default (IdleAction = "ignore")
# already means nothing suspends this host; this file makes that an explicit,
# reviewable statement instead of a silent default, so the "power and
# hibernate policy" step in docs/provisioning.md § Step 1 has a real answer.
# Contrast with hosts/enterprise-d/power.nix, which carries real
# suspend/hibernate machinery because it's a laptop.
{
  services.logind.settings.Login.IdleAction = "ignore";
}
