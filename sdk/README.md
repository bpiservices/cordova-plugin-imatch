# iMatch SDK binaries

This folder receives the native iMatch SDK binaries at install time. The zip has this layout:

```
imatch-sdk/
├── sdk-version.json       {"android": "1.5.7", "ios": "1.7.6", "minPlugin": "2.0.0"}
├── android/
│   └── imatchsdk.aar
└── ios/
    └── iMatchSDK.xcframework/
```

## Using the plugin from npm

Unzip the SDK into your Cordova project as `imatch-sdk/`, next to `config.xml`, and run
`cordova plugin add cordova-plugin-imatch`. The `scripts/stage-sdk.js` hook copies the files for each
platform into this folder. Another location can be set with `--variable IMATCH_SDK_DIR=<folder>` or
the `IMATCH_SDK_DIR` environment variable.
