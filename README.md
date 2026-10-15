# frontend-edge

Qt/QML edge console. Click a completed recording in the Recordings tab to open
its player. Playback uses the local MP4 first (including files saved before the
repository rename), then requests an authenticated server playback URL if the
local file is missing. The server API address is stored as `webApiBaseUrl` in
the application's Qt settings; the local demo default is `http://127.0.0.1:3000`.

Live preview and recording playback both have a bottom-left fullscreen button.
The button or Escape restores the workspace. Recording controls include pause,
seek, and replay without restarting the camera stream.

With the stack running and an existing Qt login, verify playback controls with:

```bash
./build-local/appDiplomaFrontendEdge --verify-recording
DIPLOMA_TEST_REMOTE=1 ./build-local/appDiplomaFrontendEdge --verify-recording
```

Set `DIPLOMA_TEST_OUTPUT` for the JSON report and screenshots, or
`DIPLOMA_TEST_RECORDING_ID` to verify a specific completed recording. To verify
live fullscreen with a stream already running:

```bash
DIPLOMA_TEST_FULLSCREEN=1 ./build-local/appDiplomaFrontendEdge --verify-camera
```
