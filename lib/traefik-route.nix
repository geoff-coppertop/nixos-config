{
  name,
  port,
  domain,
  subdomain ? name,
}: {
  routers.${name} = {
    rule = "Host(`${subdomain}.${domain}`)";
    service = name;
    tls = {};
  };
  # 127.0.0.1, not "localhost" — deterministic IPv4 loopback. "localhost" can
  # resolve to ::1 depending on system resolution order, and services with
  # strict reverse-proxy trust checks (e.g. Home Assistant's trusted_proxies,
  # which only lists 127.0.0.1) reject the request outright if the proxy
  # actually connects via ::1: confirmed live — AdGuard's route (no such
  # check) worked, homeassistant's (trusted_proxies = ["127.0.0.1"]) 400'd.
  services.${name}.loadBalancer.servers = [{url = "http://127.0.0.1:${toString port}";}];
}
