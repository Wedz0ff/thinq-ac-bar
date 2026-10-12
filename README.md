# ThinQ AC Bar

Control your LG ThinQ air conditioner from the Mac menu bar.

> Unofficial community app. Not affiliated with, endorsed by, or supported by LG Electronics. LG and ThinQ are trademarks of their respective owners and are used only to describe compatibility. LG may change or restrict API access at any time, and this app may stop working.

## What It Does

- Shows your air conditioners in a menu bar popover.
- Changes power, target temperature, mode, fan speed, swing, and energy saving.
- Shows the target temperature in the menu bar while an AC is running.
- Tells you when a newer version is available.

## Install

1. Download `ACBar.dmg` from the [latest release](https://github.com/Wedz0ff/thinq-ac-bar/releases/latest) and open it.
2. Drag `ACBar` onto the `Applications` shortcut, then open it from Applications.
3. macOS blocks the first launch because the app is not notarized by Apple. Open **System Settings > Privacy & Security**, scroll to the message about ACBar, and click **Open Anyway**. This is needed once.

Requires macOS 14 or later, on Apple Silicon or Intel. To start it with your Mac, turn on **Launch at login** in the app's settings.

## Build From Source

Needs Xcode 15 or later.

```bash
./build.sh
open ACBar.app
```

An app you build yourself is not blocked by macOS.

## Setup

1. Create a ThinQ Personal Access Token at [connect-pat.lgthinq.com](https://connect-pat.lgthinq.com).
2. Click the AC icon in the menu bar.
3. Paste the token and click **Save**.

LG requires the account's country on every request. The app sends your Mac's region (System Settings > General > Language & Region), or `US` if none is set, so that region must match the country of your LG account.

The token is stored in the macOS Keychain. It is sent only to `api-aic.lgthinq.com`.

Once a day the app asks `api.github.com` for the latest release of this repository, to offer updates. Nothing about you or your devices is sent.

Because the app is ad-hoc signed, macOS may ask for Keychain access again after each rebuild. Choose **Always Allow**.

## Development

```bash
swift test
```

## Limitations

- Americas accounts only: requests go to `api-aic.lgthinq.com`. Accounts in Europe or Asia use other LG hosts and are not supported.
- Mode and fan options and the 18-30 °C range are fixed in `Sources/ACBar/ACBarApp.swift`. They match model `RAC_056905_WW`; other models may support different values.
- Temperature changes in 1 °C steps.

## License

[MIT](LICENSE)
