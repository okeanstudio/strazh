# App update manifest

The app reads `https://auth.strazh.chat/strazh/version.json`. The source manifest
for publishing is `server/strazh/version.json`.

The manifest format is:

```json
{
  "version": "1.1.4",
  "whats_new": ["Release note"],
  "android_url": "https://strazh.chat/assets/files/strazh.apk",
  "windows_url": "https://strazh.chat/assets/files/StrazhSetup.exe",
  "download_url": "https://strazh.chat/"
}
```

`version` is required. `whats_new` is an optional list of non-empty strings;
the app still accepts older manifests that do not contain it. Download URLs are
optional and must use HTTPS. Publish this file to the manifest URL above to
update the release notes shown in the app.
