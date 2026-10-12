# ThinQ AC Bar

Control your LG ThinQ air conditioner from the Mac menu bar.

> Unofficial community app. Not affiliated with, endorsed by, or supported by LG Electronics. LG and ThinQ are trademarks of their respective owners and are used only to describe compatibility. LG may change or restrict API access at any time, and this app may stop working.

## What It Does

- Shows your air conditioners in a menu bar popover.
- Changes power, target temperature, mode, fan speed, swing, and energy saving.
- Shows the target temperature in the menu bar while an AC is running.

## Requirements

- macOS 14 or later
- Xcode 15 or later (to build)
- An LG ThinQ account with a Personal Access Token

## Build And Run

```bash
./build.sh
open ACBar.app
```

To keep it, move `ACBar.app` to `/Applications` and turn on **Launch at login** in the app's settings.

## Setup

1. Create a ThinQ Personal Access Token by following the [Home Assistant LG ThinQ guide](https://www.home-assistant.io/integrations/lg_thinq/).
2. Click the AC icon in the menu bar.
3. Paste the token, enter your country code (`BR`, `US`, ...), and click **Save**.

The token is stored in the macOS Keychain. It is sent only to `api-aic.lgthinq.com`.

Because the app is ad-hoc signed, macOS may ask for Keychain access again after each rebuild. Choose **Always Allow**.

## Development

```bash
swift test
```

## Limitations

- Americas accounts only: requests go to `api-aic.lgthinq.com`. Accounts in Europe or Asia use other LG hosts and are not supported.
- Mode and fan options and the 18-30 °C range are fixed in `Sources/ACBar/ACBarApp.swift`. They match model `RAC_056905_WW`; other models may support different values.
- Temperature changes in 1 °C steps.
