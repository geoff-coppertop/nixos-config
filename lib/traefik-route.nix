{
  name,
  port,
  domain,
  subdomain ? name,
  # Names of dynamicConfigOptions.http.middlewares entries to attach to this
  # router, e.g. ["authelia"] for forward-auth. Empty by default so existing
  # callers are unaffected; omitted entirely from the router when empty
  # rather than emitting `middlewares = [];`, since Traefik's TOML freeform
  # merge treats an explicit empty list the same as a real value for
  # conflict-detection purposes between module contributions.
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
  # 127.0.0.1, not "localhost" — deterministic IPv4 loopback. "localhost" can
  # resolve to ::1 depending on system resolution order, and services with
  # strict reverse-proxy trust checks (e.g. Home Assistant's trusted_proxies,
  # which only lists 127.0.0.1) reject the request outright if the proxy
  # actually connects via ::1: confirmed live — AdGuard's route (no such
  # check) worked, homeassistant's (trusted_proxies = ["127.0.0.1"]) 400'd.
  services.${name}.loadBalancer.servers = [{url = "http://127.0.0.1:${toString port}";}];
}
