# flutter_communication_avatar (local patch)

This is the MIT-licensed `flutter_communication_avatar` 1.1.0 plugin source.
The local copy is used because the published Android source passed nullable
strings to non-null Kotlin APIs after checking them with a custom helper, and
its iOS method-channel call omitted a required Swift argument label. These
compile fixes preserve plugin behavior. The Android notification tap is also
connected to the app's existing chat navigation callback.

The upstream package is available at
https://github.com/HungNM-Developer/flutter_communication_avatar.
