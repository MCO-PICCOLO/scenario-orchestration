# Guest Arduino — LED boards

Arduino sketches and setup for the **guest-side LED boards** used in the
resource-isolation demo. Two Arduino UNO R4 WiFi boards drive the two LEDs whose
timing is compared: one controlled via TIMPANI signals, the other on a plain
interval.

> Instructions assume CentOS Stream / x86_64, with `arduino-cli` installed.

## Contents

```
arduino/
├── 99-arduino-led.rules   # udev rules: stable /dev symlinks per board
├── compile.sh             # compile both sketches
├── install.sh             # upload both sketches to their boards

../../../common/arduino/   # shared sketches (also used by single_node)
├── ardn_led_timpani/      # TIMPANI signal-based LED sketch
└── ardn_led_normal/       # normal sleep-based LED sketch
```

Board FQBN: `arduino:renesas_uno:unor4wifi`

## Boards & device symlinks

The udev rules map each board (by USB serial) to a stable symlink:

| Sketch | Symlink | Role |
|--------|---------|------|
| `ardn_led_timpani` | `/dev/arduino_led_timpani` | LED driven by TIMPANI signal-based control |
| `ardn_led_normal`  | `/dev/arduino_led_normal`  | LED driven by normal sleep-based control |

## Setup

### 1. Install udev rules (one-time)

```bash
sudo cp 99-arduino-led.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Verify the symlinks appear after plugging in the boards:

```bash
ls -l /dev/arduino_led_timpani /dev/arduino_led_normal
```

> If the serials in `99-arduino-led.rules` don't match your boards, update the
> `ATTRS{serial}` values (find them with `arduino-cli board list`).

### 2. Compile

```bash
./compile.sh
```

### 3. Upload

```bash
./install.sh
```

`install.sh` resolves each symlink to its real port and uploads the matching
sketch. Re-run after any sketch change.

## Notes

- These boards only drive the LEDs; the LED on/off timing is commanded by the
  guest LED controllers (`../led-timpani-controller`, `../led-normal-controller`).
- For the full multi-node demo procedure, see
  [../../test_script/README.md](../../test_script/README.md).