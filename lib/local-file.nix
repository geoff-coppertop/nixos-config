# Copy one local file (or directory) into the store as its own
# content-addressed object, hashed on that path's content alone.
#
# A bare path literal such as `./files/face.png`, written in a .nix file that
# is itself part of this flake, resolves to a *subpath* of the single
# whole-repo store copy Nix makes of `self` before evaluation. Coercing it to a
# string — `.source = ./x`, `${./x}` inside a builder, `toString ./x` — embeds
# a value whose store identity therefore moves whenever any tracked file
# anywhere in the repo changes, however unrelated.
#
# `builtins.path` NAR-hashes just the given path's own content, independent of
# where it sat during evaluation, which breaks that coupling.
#
# See docs/architecture.md § Local Files As Build Inputs.
{
  path,
  name ? baseNameOf (toString path),
}:
builtins.path {
  inherit path name;
}
