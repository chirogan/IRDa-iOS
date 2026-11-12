# IRDa for iOS

Swift/SwiftUI port of MarcusD's IRDa (Android) for the 3DS InputRedirection homebrew.
Reads a Bluetooth/USB game controller on iPhone/iPad (GameController framework) and streams the
20-byte input packet over UDP to `<3DS IP>:4950` every 15 ms. Packet encoding in
`Sources/CitroPad.swift` is a line-for-line port of the original `CitroPad.Pack()`.

## Get the IPA (no Mac needed)
1. Create a GitHub repo and push this folder.
2. Actions tab -> "Build IPA" -> Run workflow (it also runs on every push).
3. Download the `IRDa-ipa` artifact -> unzip -> `IRDa.ipa` (unsigned).

## Install
Sideload with AltStore, SideStore or Sideloadly using your Apple ID (they sign it for you).

## Use
Pair the controller in iOS Settings -> Bluetooth, open IRDa, enter the 3DS IP, tap Connect.
Allow "Local Network" access when asked. Keep the app in the foreground (iOS suspends it otherwise);
"Black screen" dims the display to save battery.
