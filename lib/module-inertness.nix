# Asserts the invariant that makes modules/default.nix safe to import wholesale:
# a module must contribute nothing to a host that has not set its custom.*
# option. Without this, an ungated module lands on all three hosts the moment
# it is added to modules/default.nix, and nothing notices.
#
# This evaluates rather than greps. Each module is applied to a probe host that
# sets no custom.* option, so its mkIf conditions are computed against a real
# config — optionalAttrs, mkMerge, and a condition spanning several options all
# resolve for real, where a textual search for `mkIf` would pass them.
#
# It asks what each module contributes, not what the merged option tree ended up
# with. Walking the merged tree is the more direct question, but answering it
# means forcing every nixpkgs option's definitions, and a minimal host cannot
# survive that: lanzaboote alone defaults publicKeyFile to
# "${cfg.pkiBundle}/keys/db/db.key", which is a coercion error while pkiBundle
# is null. builtins.tryEval does not help — it catches throw and assert, not
# type errors. Per-module has better diagnostics anyway: it names the file.
{
  pkgs,
  probe,
  modulesDir,
}: let
  inherit (pkgs) lib;

  moduleNames =
    lib.filter (name: name != "default.nix")
    (lib.attrNames
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir modulesDir)));

  # Applied the way the module system applies it. Every module here takes a
  # subset of {config, lib, pkgs} and ends in `...`, so the superset is safe.
  applied = name: let
    m = import (modulesDir + "/${name}");
  in
    if lib.isFunction m
    then
      m {
        inherit lib pkgs;
        inherit (probe) config options;
      }
    else m;

  # Inert means "can contribute no definition": an mkIf whose condition came
  # out false, an mkMerge whose parts are all inert, or an attrset whose values
  # are all inert — which includes {}, what optionalAttrs and a mapAttrs over an
  # unset option both produce. Anything else is live.
  inert = value:
    if !(lib.isAttrs value) || lib.isDerivation value
    then false
    else if value._type or "" == "if"
    then !value.condition || inert value.content
    else if value._type or "" == "merge"
    then lib.all inert value.contents
    else if value ? _type
    then false
    else lib.all inert (lib.attrValues value);

  # A check that cannot fail is worth nothing, so `inert` is exercised against
  # fixtures every run rather than trusted. This is the negative test, and it
  # runs in CI with everything else instead of being a manual step.
  selfTest = {
    "an ungated attrset is live" = !(inert {environment.variables.PROBE = "1";});
    "mkIf true is live" = !(inert (lib.mkIf true {environment.variables.PROBE = "1";}));
    "mkIf false is inert" = inert (lib.mkIf false {environment.variables.PROBE = "1";});
    "mkMerge of inert parts is inert" = inert (lib.mkMerge [(lib.mkIf false {a = 1;}) {}]);
    "the empty attrset is inert" = inert {};
  };

  selfTestFailures = lib.attrNames (lib.filterAttrs (_: passed: !passed) selfTest);

  offendersFor = name: let
    m = applied name;
  in
    lib.optional (m ? config && !(inert m.config)) "${name} — config is not gated"
    ++ lib.optional ((m.imports or []) != []) "${name} — imports unconditionally";

  offenders = lib.concatMap offendersFor moduleNames;

  report = ''
    modules/ is imported whole by every host, so each module must contribute
    nothing until that host sets its custom.* option. Applied to a probe host
    that sets none, these did not come out inert:

      ${lib.concatStringsSep "\n      " offenders}

    Fix by gating the module's config behind mkIf, or — if the setting
    genuinely belongs on every host — move it to profiles/common/, which every
    host imports by name.
  '';
in
  if selfTestFailures != []
  then throw "lib/module-inertness.nix cannot be trusted — its own inertness test failed on: ${lib.concatStringsSep ", " selfTestFailures}"
  else if offenders != []
  then throw report
  else pkgs.runCommand "modules-inert" {} "touch $out"
