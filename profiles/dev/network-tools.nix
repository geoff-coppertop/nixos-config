{pkgs, ...}: {
  # dig/nslookup/host — for debugging DNS directly against a specific
  # resolver/port (e.g. `dig @127.0.0.1 -p 5335` against unbound on defiant),
  # which curl/getent can't do.
  environment.systemPackages = [pkgs.dnsutils];
}
