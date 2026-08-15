import argparse
import configparser
import os
import select
import subprocess
import sys

from evdev import InputDevice, ecodes, list_devices

CONFIG = os.path.expanduser("~/.config/discord-cough-mute/config")


def load_config():
    parser = configparser.ConfigParser()
    parser.read(CONFIG)
    if "button" not in parser:
        return None
    return parser["button"]["device"], int(parser["button"]["code"])


def save_config(device, code):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    parser = configparser.ConfigParser()
    parser["button"] = {"device": device, "code": str(code)}
    with open(CONFIG, "w") as handle:
        parser.write(handle)


def learn():
    devices = [InputDevice(path) for path in list_devices()]
    if not devices:
        sys.exit("no input devices found")
    print("Press the button you want as the cough button...")
    fds = {dev.fd: dev for dev in devices}
    while True:
        ready, _, _ = select.select(fds, [], [])
        for fd in ready:
            for event in fds[fd].read():
                if event.type == ecodes.EV_KEY and event.value == 1:
                    dev = fds[fd]
                    save_config(dev.path, event.code)
                    print("Saved: %s code %d" % (dev.path, event.code))
                    return


def discord_source_outputs():
    out = subprocess.run(
        ["pactl", "list", "source-outputs"],
        capture_output=True, text=True, check=False,
    ).stdout
    indexes = []
    current = None
    is_discord = False
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("Source Output #"):
            if current is not None and is_discord:
                indexes.append(current)
            current = stripped.split("#", 1)[1]
            is_discord = False
        elif "application.name" in stripped and "Discord" in stripped:
            is_discord = True
    if current is not None and is_discord:
        indexes.append(current)
    return indexes


def set_discord_mute(muted):
    for index in discord_source_outputs():
        subprocess.run(
            ["pactl", "set-source-output-mute", index, "1" if muted else "0"],
            check=False,
        )


def run():
    config = load_config()
    if config is None:
        sys.exit("no button configured; run: discord-cough-mute --learn")
    path, code = config
    device = InputDevice(path)
    for event in device.read_loop():
        if event.type == ecodes.EV_KEY and event.code == code:
            set_discord_mute(event.value == 1)


def main():
    parser = argparse.ArgumentParser(description="Mute Discord while a HOTAS cough button is held")
    parser.add_argument("--learn", action="store_true", help="capture the next button press and save it")
    args = parser.parse_args()
    if args.learn:
        learn()
    else:
        run()


if __name__ == "__main__":
    main()
