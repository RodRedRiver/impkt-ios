# IMPKT pilot app, iOS

The pilot page, on an iPhone, with a real Bluetooth radio and a firmware
updater. It is a shell around the page rather than a rewrite of it.

```
IMPKT/
  IMPKTApp.swift        two tabs, Test and Update
  PilotPage.swift       WKWebView + the bridge both ways
  WrapCentral.swift     one CoreBluetooth manager for the whole app
  UpdateView.swift      firmware over the air, using Nordic's DFU library
  Info.plist            Bluetooth usage strings Apple requires
  Resources/
    bridge.js           navigator.bluetooth, implemented on CoreBluetooth
    firmware.zip        the DFU package a phone installs
    firmware-version.txt
    Web/index.html      a copy of stryke-systems/test/index.html
project.yml             XcodeGen project definition
sync-web.sh             refresh the page and the firmware from their sources
```

## Why it is shaped like this

iOS has no Web Bluetooth and Apple has never shipped it, so the page cannot talk
to a wrap in Safari. Everything else in the page works there perfectly. So the
page is kept whole and only its radio is replaced: `bridge.js` installs a
`navigator.bluetooth` that forwards to CoreBluetooth, and the page cannot tell
the difference. One page, one set of wording, one place a change lands.

Wraps are found by the punch service UUID in their advertisement, never by name.
Boards are being named by hand now (Impktband 1, 2, 3), and anything matching on
a name prefix would have stopped finding them the day one was renamed.

## Build it

1. Install Xcode from the App Store. This is the only real prerequisite and it
   is a large download. If the App Store refuses it, run Software Update first:
   current Xcode wants a newer macOS than 13.4.
2. `./sync-web.sh` in this directory. It copies the page and the newest DFU
   package out of `boxing-fw`, so the app always ships the firmware you last
   built.
3. Make the project, either way round:
   - `brew install xcodegen && xcodegen generate`, then open `IMPKT.xcodeproj`.
   - Or by hand in Xcode: File > New > Project > iOS App, name it IMPKT,
     interface SwiftUI, save it here. Delete the two files the template makes,
     drag in the `IMPKT` folder, and add the package
     `https://github.com/NordicSemiconductor/IOS-DFU-Library` under
     File > Add Package Dependencies, product `NordicDFU`. Point the target's
     Info.plist setting at `IMPKT/Info.plist`.
4. In Signing & Capabilities pick your team. Now that you have a developer
   account this is one dropdown.
5. Run it on a real iPhone. Not the simulator: the simulator has no Bluetooth
   radio and will find nothing, which looks like a bug and is not one.

## Sending it to somebody else

TestFlight. Archive in Xcode, upload, add them by email, and they install from
the TestFlight app. That is what makes the firmware update useful at a distance:
they get the app with the firmware inside it, and they update their own wraps in
their own room. Bluetooth is a few metres, so the phone has to be next to the
wrap. What crosses the border is the app, not the radio.

## Updating firmware from the app

The wraps speak Nordic's legacy DFU protocol, which the Adafruit bootloader
implements and Nordic's iOS library drives. The Update tab lists every wrap it
can see, and one press does the whole job: the wrap reboots into its bootloader,
takes the image, checks it, and restarts on the new firmware. A failed update is
safe; the wrap keeps what it had.

Because the image is bundled, a firmware release is an app release. Run
`./sync-web.sh`, bump the version in `project.yml`, archive, upload. That is
deliberate for a pilot: nobody can pair a stale zip with a current app, and
"what firmware is on my wraps" has one answer.
