# Uploading to App Store Connect

Screenshots and previews belong to an **app version**. Create the new version
first (Distribution > the platform's "+" > version number). It copies the
previous version's text and media; replace the media on the new version only.
The live listing keeps its media until the new version is released, so
nothing a customer sees changes during preparation.

## On the new version

1. Select the build (it must have finished processing).
2. What's New in This Version, Promotional Text (changeable any time without
   review), and any description or keyword changes.
3. Media: remove an out-of-date App Preview video (it plays before the
   screenshots), then replace each screenshot set.
4. App Store Version Release: manual or automatic after review; phased release
   (7 days of automatic-update rollout, pausable) is set here too.
5. Save. Submitting for review is a separate, deliberate step for the owner.

## Through the API (preferred for many sizes)

Every asset goes through Apple's three-step reservation: create the
screenshot record (returns upload operations), PUT the bytes to each
operation's URL, then PATCH `uploaded: true` with the file's MD5. Processing
is asynchronous; poll each asset until `COMPLETE` or `FAILED`.

- Auth: an App Store Connect API key (Users and Access > Integrations), App
  Manager role, ES256 JWT. The key file lives outside every repository.
- Flow: app by bundle id > `appStoreVersions` filtered by version string >
  `appStoreVersionLocalizations` for the locale > `appScreenshotSets` per
  display type (create if missing) > upload into it in filename order. A
  `--replace` mode deletes the set's existing screenshots first.
- **Display types keep old device names.** The API's enum was not renamed when
  accepted sizes grew, so the 6.9" class (1320x2868) uploads as
  `APP_IPHONE_67` and the 13" iPad (2064x2752) as `APP_IPAD_PRO_3GEN_129`
  (both used in a real upload, September 2026). fastlane's `deliver`
  (deliver/lib/deliver/app_screenshot.rb) is a maintained source for the
  rest of the mapping. Look up every other class (6.5", 6.3", 6.1", 5.5",
  4.7", iPhone Duo) in the current `ScreenshotDisplayType` reference before
  uploading; do not guess from the device name.
- Previews follow the same reservation flow under `appPreviewSets`.

A working uploader of this shape lives in a sibling app's repo
(`upload_store_media.py`: dry run, `--replace`, `--wait`); copy and
parameterise it rather than rewriting.

## Through the web

Media Manager on the version page ("View All Sizes in Media Manager") lists
every display class; drag the PNGs in store order into each. Slower for eight
or more classes, but needs no key. Uploads that fail on size or alpha are
rejected immediately with a message.
