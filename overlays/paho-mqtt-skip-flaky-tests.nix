# Why this overlay exists (transient, remove per the note at the bottom):
#
# paho-mqtt is byte-identical between the nixpkgs we moved off (26.05) and the
# one we moved to (26.11) — same 2.1.0, same upstream test config (only
# test_01_zero_length_clientid disabled). On 26.05 the aarch64 build was already
# in cache.nixos.org, so CI *substituted* the prebuilt output and paho's test
# suite never ran here. On the fresh 26.11 pin the aarch64 output is not cached
# yet (Hydra lag on a channel bump), so CI builds paho from source on the ARM
# runner — and its live-broker tests run in our CI for the first time.
#
# Those live-broker tests spin up a fake broker and client subprocesses and do
# real socket round-trips with timing assumptions. On the CI runner they flake
# nondeterministically (a different subset fails each run: "1 failed, 3 errors"
# one run, "6 errors" the next), spuriously failing the defiant (Home Assistant)
# build. The library itself is fine.
#
# Fix: disable the whole live-broker integration suite (tests/lib) — the same
# directory nixpkgs itself already carves exceptions out of via disabledTestPaths
# — plus the fake-broker socket tests in tests/test_client.py that hit the same
# timing-sensitive FakeBroker.receive_packet() path (each has independently
# flaked in CI with a ConnectionResetError or similar; this list started with
# just the two callback-flow tests and grew as more flaked under CI's timing —
# expect it may grow further until the overlay is removed). This keeps every
# pure unit test (matcher, reason codes, packet types, properties, subscribe
# options) running, and restores the effective coverage our CI actually had
# before: those network tests were never validated here — they arrived
# prebuilt from the binary cache.
#
# pythonPackagesExtensions covers whichever python Home Assistant is built
# against. Remove this overlay once the aarch64 build for our pinned nixpkgs is
# cache-served again (so paho is substituted, not built) or upstream disables
# these tests itself.
_final: prev: {
  pythonPackagesExtensions =
    prev.pythonPackagesExtensions
    ++ [
      (_pyfinal: pyprev: {
        paho-mqtt = pyprev.paho-mqtt.overridePythonAttrs (old: {
          disabledTestPaths =
            (old.disabledTestPaths or [])
            ++ ["tests/lib"];
          disabledTests =
            (old.disabledTests or [])
            ++ [
              "test_callback_v1_mqtt3"
              "test_callback_v2_mqtt3"
              "test_publish_before_connect"
            ];
        });
      })
    ];
}
