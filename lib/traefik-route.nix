{
  name,
  port,
  domain,
  subdomain ? name,
  # Router-level middleware references (Traefik's own "name@provider" form,
  # e.g. "authelia@file" for modules/authelia.nix's forward-auth
  # middleware). Empty by default — most routes carry no auth middleware,
  # and a service's own login (or none) is the only gate. See
  # docs/homelab-network.md § Authelia Forward-Auth for which routes opt in
  # and which two (lldap's own admin UI, Authelia's own portal) must never
  # carry this, to avoid a self-lockout if lldap is down or mid-bootstrap.
  middlewares ? [],
}: {
  routers.${name} =
    {
      rule = "Host(`${subdomain}.${domain}`)";
      service = name;
      tls = {};
    }
    // (
      if middlewares != []
      then {inherit middlewares;}
      else {}
    );
  # 127.0.0.1, not "localhost" — deterministic IPv4 loopback. "localhost"
  # can resolve to ::1 depending on system resolution order, and services
  # with strict reverse-proxy trust checks (e.g. Home Assistant's
  # trusted_proxies, listing only 127.0.0.1) reject the request outright if
  # the proxy connects via ::1: AdGuard's route (no such check) worked,
  # homeassistant's 400'd.
  services.${name}.loadBalancer.servers = [{url = "http://127.0.0.1:${toString port}";}];
}
