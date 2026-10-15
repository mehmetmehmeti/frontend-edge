import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import DiplomaFrontendEdge

ApplicationWindow {
    id: root
    width: 1360
    height: 820
    minimumWidth: 960
    minimumHeight: 680
    visible: true
    title: "Capture Console | Edge"
    font.family: "Arial"
    font.pixelSize: 13
    color: root.colors.background

    readonly property var colors: appPalette

    QtObject {
        id: appPalette
        readonly property color background: "#f6f7f9"
        readonly property color surface: "#ffffff"
        readonly property color surfaceAlt: "#eff1f5"
        readonly property color text: "#20242c"
        readonly property color muted: "#717783"
        readonly property color border: "#e1e4e9"
        readonly property color accent: "#245de3"
        readonly property color accentSoft: "#eef3ff"
        readonly property color blue: "#2563eb"
        readonly property color warning: "#a16207"
        readonly property color danger: "#b42318"
        readonly property color dark: "#15171b"
    }

    Settings {
        id: settings
        property string authToken: ""
        property string apiBaseUrl: "http://127.0.0.1:3002"
        property string deviceId: "edge-dev-001"
        property string email: ""
        property string webApiBaseUrl: "http://127.0.0.1:3000"
    }

    property string apiBaseUrl: settings.apiBaseUrl
    property string defaultDeviceId: settings.deviceId.length > 0 ? settings.deviceId : "edge-dev-001"
    property string token: settings.authToken
    property var currentUser: ({})
    property var users: []
    property var devices: []
    property var streams: []
    property var videos: []
    property var commands: []
    property string email: settings.email
    property string password: ""
    property string fullName: ""
    property int workspaceIndex: 0
    property string mode: "login"
    property string statusText: "Ready"
    property string statusKind: "info"
    property string selectedStreamId: ""
    property string selectedDeviceId: defaultDeviceId
    property string streamTitle: "Edge local stream"
    property int activeRequests: 0
    readonly property bool busy: activeRequests > 0
    property bool refreshing: false
    property bool syncConnected: false
    property bool streamEdgeAvailable: false
    property bool streamEdgeStreaming: false
    property bool streamEdgeRecording: false
    property string streamEdgeStatus: "unknown"
    property string streamEdgeMessage: ""
    property string previewPipeline: ""
    property string lastRefreshText: "Not refreshed yet"
    property int requestCounter: 0
    property var selectedRecording: ({})
    property string recordingMessage: ""
    property string fullscreenTarget: ""
    property int videoWindowVisibility: Window.Windowed

    readonly property var selectedStream: root.findById(root.streams, root.selectedStreamId)
    readonly property var selectedDevice: root.findById(root.devices, root.selectedDeviceId)
    readonly property var activeRecording: root.findActiveRecording()
    readonly property var latestCommand: root.commands.length > 0 ? root.commands[0] : ({})
    readonly property int liveStreamCount: root.countByStatus(root.streams, "live")
    readonly property int recordingCount: root.countByStatus(root.videos, "recording")

    function setStatus(message, kind) {
        root.statusText = message || ""
        root.statusKind = kind || "info"
    }

    function request(path, method, body, callback, options) {
        const xhr = new XMLHttpRequest()
        const requestId = ++root.requestCounter
        const silent = options && options.silent
        let settled = false
        function settle() {
            if (!settled && !silent) root.activeRequests = Math.max(0, root.activeRequests - 1)
            settled = true
        }
        const baseUrl = options && options.baseUrl ? options.baseUrl : root.apiBaseUrl
        xhr.open(method || "GET", baseUrl.replace(/\/+$/, "") + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (root.token && root.token.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + root.token)

        if (!silent)
            root.activeRequests += 1

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            settle()

            let payload = ({})
            try {
                payload = xhr.responseText.length > 0 ? JSON.parse(xhr.responseText) : ({})
            } catch (error) {
                payload = ({ message: xhr.responseText })
            }

            if (xhr.status < 200 || xhr.status >= 300) {
                const message = payload.message || payload.error || ("Request failed: " + xhr.status)
                root.setStatus(message, "error")
                if (options && options.onError) options.onError(message)
                if (xhr.status === 401)
                    root.logout(false)
                return
            }

            if (callback)
                callback(payload)
        }
        xhr.onerror = function() {
            settle()
            const message = "Could not reach backend at " + baseUrl
            root.setStatus(message, "error")
            if (options && options.onError) options.onError(message)
        }
        xhr.send(body ? JSON.stringify(body) : undefined)
    }

    function loginOrRegister() {
        if (root.email.trim().length === 0 || root.password.trim().length === 0) {
            root.setStatus("Email and password are required", "error")
            return
        }
        if (root.mode === "register" && root.fullName.trim().length === 0) {
            root.setStatus("Full name is required", "error")
            return
        }

        const payload = root.mode === "register"
            ? ({ email: root.email, password: root.password, fullName: root.fullName, role: "OPERATOR" })
            : ({ email: root.email, password: root.password })
        root.request("/auth/" + root.mode, "POST", payload, function(response) {
            root.token = response.token || ""
            settings.authToken = root.token
            settings.email = root.email
            root.currentUser = response.user || ({})
            root.password = ""
            root.setStatus("Authenticated", "success")
            root.refreshAll(false)
        })
    }

    function logout(showMessage) {
        recordingDialog.close()
        root.exitVideoFullscreen()
        root.token = ""
        settings.authToken = ""
        root.currentUser = ({})
        root.users = []
        root.devices = []
        root.streams = []
        root.videos = []
        root.commands = []
        root.syncConnected = false
        root.streamEdgeAvailable = false
        if (showMessage !== false)
            root.setStatus("Signed out", "info")
    }

    function refreshAll(silent) {
        if (!root.token)
            return

        root.refreshing = true
        root.request("/auth/me", "GET", null, function(response) {
            root.currentUser = response.user || ({})
        }, { silent: silent })
        root.request("/users", "GET", null, function(response) {
            root.users = response.users || []
        }, { silent: silent })
        root.request("/devices", "GET", null, function(response) {
            root.devices = response.devices || []
            if (!root.findById(root.devices, root.selectedDeviceId) && root.devices.length > 0)
                root.selectedDeviceId = root.devices[0].id || root.defaultDeviceId
        }, { silent: silent })
        root.request("/streams", "GET", null, function(response) {
            root.streams = response.streams || []
            root.selectedStreamId = root.preferredStreamId(root.streams, root.selectedStreamId)
        }, { silent: silent })
        root.request("/videos", "GET", null, function(response) {
            root.videos = response.videos || []
        }, { silent: silent })
        root.request("/commands", "GET", null, function(response) {
            root.commands = response.commands || []
            root.refreshing = false
            root.lastRefreshText = Qt.formatDateTime(new Date(), "hh:mm:ss")
            root.syncConnected = true
            if (!silent)
                root.setStatus("Data refreshed", "success")
        }, { silent: silent })
    }

    function registerCurrentDevice() {
        settings.deviceId = root.selectedDeviceId
        root.request("/devices", "POST", {
            id: root.selectedDeviceId,
            name: root.selectedDeviceId,
            status: "online",
            source_ready: true,
            streaming: root.streamEdgeStreaming,
            recording: root.streamEdgeRecording,
            last_seen_at: new Date().toISOString()
        }, function() {
            root.setStatus("Device registered", "success")
            root.refreshAll(true)
        })
    }

    function startCurrentStream() {
        if (!root.selectedDeviceId) {
            root.setStatus("Select a device first", "error")
            return
        }
        root.request("/streams/start", "POST", {
            device_id: root.selectedDeviceId,
            title: root.streamTitle
        }, function(response) {
            root.selectedStreamId = response.stream ? response.stream.id : ""
            root.setStatus("Start stream command queued", "success")
            root.refreshAll(true)
        })
    }

    function hasPendingCommand() {
        return root.commands.some(function(command) {
            return command.device_id === root.selectedDeviceId &&
                ["pending", "claimed", "processing"].indexOf(command.status) >= 0
        })
    }

    function stopCurrentStream() {
        if (!root.selectedStreamId) {
            root.setStatus("Select a stream first", "error")
            return
        }
        root.request("/streams/" + root.selectedStreamId + "/stop", "POST", {}, function() {
            root.setStatus("Stop stream command queued", "success")
            root.refreshAll(true)
        })
    }

    function startCurrentRecording() {
        if (!root.selectedStreamId) {
            root.setStatus("Select a stream first", "error")
            return
        }
        root.request("/streams/" + root.selectedStreamId + "/recordings/start", "POST", {
            title: ((root.selectedStream && root.selectedStream.title) ? root.selectedStream.title : "Stream") + " recording"
        }, function() {
            root.setStatus("Start recording command queued", "success")
            root.refreshAll(true)
        })
    }

    function stopCurrentRecording() {
        if (!root.selectedStreamId) {
            root.setStatus("Select a stream first", "error")
            return
        }
        root.request("/streams/" + root.selectedStreamId + "/recordings/stop", "POST", {
            video_id: root.activeRecording ? root.activeRecording.id : undefined
        }, function() {
            root.setStatus("Stop recording command queued", "success")
            root.refreshAll(true)
        })
    }

    function checkStreamEdgeStatus() {
        const xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:8081/stream/status")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status < 200 || xhr.status >= 300) {
                root.streamEdgeAvailable = false
                root.streamEdgeStreaming = false
                root.previewPipeline = ""
                root.streamEdgeStatus = "offline"
                root.streamEdgeMessage = "stream-edge unavailable"
                return
            }
            let payload = ({})
            try {
                payload = JSON.parse(xhr.responseText)
            } catch (error) {
                payload = ({})
            }
            root.streamEdgeAvailable = true
            root.streamEdgeStatus = String(payload.status || "ok")
            root.streamEdgeStreaming = payload.streaming === true
            root.streamEdgeRecording = payload.recording === true
            const bridge = payload.publisher ? payload.publisher.framebridge_export : null
            root.previewPipeline = payload.streaming && bridge && bridge.started && bridge.width
                ? 'shmsrc socket-path="' + bridge.socket_path + '" is-live=true do-timestamp=true ! '
                  + 'video/x-raw,format=' + bridge.gst_format + ',width=' + bridge.width
                  + ',height=' + bridge.height + ',framerate=' + bridge.frame_rate_num + '/' + bridge.frame_rate_den
                  + ' ! queue max-size-buffers=1 leaky=downstream ! videoconvert ! video/x-raw,format=RGBA'
                  + ' ! appsink name=preview max-buffers=1 drop=true sync=false'
                : ""
            root.streamEdgeMessage = String(payload.lastError || payload.sourceSignalError || payload.message || "")
        }
        xhr.onerror = function() {
            root.streamEdgeAvailable = false
            root.streamEdgeStreaming = false
            root.previewPipeline = ""
            root.streamEdgeStatus = "offline"
            root.streamEdgeMessage = "stream-edge unavailable"
        }
        xhr.send()
    }

    function findById(list, id) {
        if (!list || !id)
            return null
        for (let i = 0; i < list.length; ++i) {
            if (String(list[i].id || "") === String(id))
                return list[i]
        }
        return null
    }

    function findActiveRecording() {
        if (!root.selectedStreamId)
            return null
        for (let i = 0; i < root.videos.length; ++i) {
            const item = root.videos[i]
            if (String(item.stream_id || "") === root.selectedStreamId && String(item.status || "") === "recording")
                return item
        }
        return null
    }

    function preferredStreamId(list, currentId) {
        const current = root.findById(list, currentId)
        if (current && String(current.status || "").toLowerCase() === "live")
            return current.id || ""

        for (let i = 0; list && i < list.length; ++i) {
            const item = list[i]
            if (String(item.status || "").toLowerCase() === "live")
                return item.id || ""
        }

        if (current)
            return current.id || ""

        return list && list.length > 0 ? (list[0].id || "") : ""
    }

    function countByStatus(list, status) {
        let count = 0
        for (let i = 0; list && i < list.length; ++i) {
            if (String(list[i].status || "").toLowerCase() === status)
                ++count
        }
        return count
    }

    function statusColor(status) {
        const normalized = String(status || "").toLowerCase()
        if (normalized === "live" || normalized === "streaming" || normalized === "online" || normalized === "completed" || normalized === "active")
            return "#23815c"
        if (normalized === "starting" || normalized === "pending" || normalized === "claimed" || normalized === "processing" || normalized === "uploading" || normalized === "stopping")
            return root.colors.warning
        if (normalized === "error" || normalized === "failed" || normalized === "recording")
            return root.colors.danger
        return root.colors.muted
    }

    function formatDateTime(value) {
        if (!value)
            return "never"
        const parsed = Date.parse(value)
        if (isNaN(parsed))
            return String(value)
        return Qt.formatDateTime(new Date(parsed), "yyyy-MM-dd hh:mm:ss")
    }

    function openRecording(video) {
        if (!video || ["completed", "uploading"].indexOf(video.status) < 0) {
            root.setStatus("This recording is not ready for playback", "error")
            return
        }
        root.selectedRecording = video
        root.recordingMessage = "Opening recording"
        recordingPreview.sourcePipeline = ""
        recordingDialog.open()
        if (recordingPreview.openRecording(String(video.edge_local_path || ""))) {
            root.recordingMessage = ""
            return
        }
        root.request("/videos/" + encodeURIComponent(video.id) + "/playback", "POST", {}, function(response) {
            if (!recordingDialog.opened || root.selectedRecording.id !== video.id) return
            root.recordingMessage = recordingPreview.openRecording(response.url || "")
                ? "" : "Recording file is unavailable"
        }, {
            baseUrl: settings.webApiBaseUrl,
            onError: function(message) { root.recordingMessage = message }
        })
    }

    function toggleVideoFullscreen(target) {
        if (root.fullscreenTarget === target) {
            root.exitVideoFullscreen()
        } else {
            root.videoWindowVisibility = root.visibility
            root.fullscreenTarget = target
            root.showFullScreen()
        }
    }

    function exitVideoFullscreen() {
        if (!root.fullscreenTarget) return
        root.fullscreenTarget = ""
        if (root.videoWindowVisibility === Window.Maximized) root.showMaximized()
        else root.showNormal()
    }

    function playbackTime(milliseconds) {
        const seconds = Math.floor(Math.max(0, milliseconds) / 1000)
        return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + seconds % 60
    }

    Rectangle {
        id: fullscreenHost
        objectName: "videoFullscreenHost"
        parent: Overlay.overlay
        anchors.fill: parent
        z: 10000
        visible: root.fullscreenTarget.length > 0
        color: root.colors.dark
        Shortcut { sequence: "Escape"; enabled: root.fullscreenTarget.length > 0; onActivated: root.exitVideoFullscreen() }
    }

    Dialog {
        id: recordingDialog
        objectName: "recordingDialog"
        anchors.centerIn: parent
        width: Math.min(root.width - 64, 1040)
        height: Math.min(root.height - 64, 700)
        modal: true
        closePolicy: root.fullscreenTarget ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        title: root.selectedRecording.title || "Recording"
        standardButtons: Dialog.Close
        onClosed: {
            if (root.fullscreenTarget === "recording") root.exitVideoFullscreen()
            recordingPreview.sourcePipeline = ""
            root.selectedRecording = ({})
        }
        contentItem: Item {
          Rectangle {
            id: recordingSurface
            anchors.fill: parent
            color: root.colors.dark
            clip: true
            states: State {
                name: "fullscreen"
                when: root.fullscreenTarget === "recording"
                ParentChange {
                    target: recordingSurface
                    parent: fullscreenHost
                }
            }
            VideoPreviewItem {
                id: recordingPreview
                objectName: "recordingPreview"
                anchors.fill: parent
                anchors.bottomMargin: 56
            }
            Label {
                anchors.centerIn: recordingPreview
                width: parent.width - 48
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "white"
                visible: recordingPreview.playbackError.length > 0 || !recordingPreview.liveFrameActive
                text: recordingPreview.playbackError || root.recordingMessage || "Loading recording"
            }
            RowLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: 12
                spacing: 12
                VideoToolButton {
                    objectName: "recordingFullscreenButton"
                    text: "⛶"
                    tooltip: root.fullscreenTarget === "recording" ? "Exit fullscreen" : "Fullscreen"
                    onClicked: root.toggleVideoFullscreen("recording")
                }
                VideoToolButton {
                    objectName: "recordingPlayButton"
                    text: recordingPreview.paused || recordingPreview.playbackFinished ? "▶" : "Ⅱ"
                    tooltip: recordingPreview.paused || recordingPreview.playbackFinished ? "Play" : "Pause"
                    enabled: recordingPreview.durationMs > 0 && !recordingPreview.playbackError
                    onClicked: {
                        if (recordingPreview.playbackFinished) {
                            recordingPreview.seek(0)
                            recordingPreview.paused = false
                        } else recordingPreview.paused = !recordingPreview.paused
                    }
                }
                Slider {
                    objectName: "recordingSeekSlider"
                    Layout.fillWidth: true
                    from: 0; to: Math.max(1, recordingPreview.durationMs)
                    value: recordingPreview.positionMs
                    enabled: recordingPreview.durationMs > 0
                    onMoved: recordingPreview.seek(value)
                }
                Label {
                    text: root.playbackTime(recordingPreview.positionMs) + " / " + root.playbackTime(recordingPreview.durationMs)
                    color: "#e6e8eb"
                    font.pixelSize: 12
                }
            }
          }
        }
    }

    Timer {
        running: root.token.length > 0
        repeat: true
        interval: 2500
        onTriggered: root.refreshAll(true)
    }

    Timer {
        running: root.token.length > 0
        repeat: true
        interval: 1500
        triggeredOnStart: true
        onTriggered: root.checkStreamEdgeStatus()
    }

    Component.onCompleted: {
        if (root.token.length > 0)
            root.refreshAll(true)
    }

    background: Rectangle { color: root.colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 82
            color: root.colors.surface
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 28
                spacing: 18
                Rectangle {
                    Layout.preferredWidth: 36; Layout.minimumWidth: 36; Layout.maximumWidth: 36
                    height: 36; radius: 6; color: root.colors.accentSoft
                    Label { anchors.centerIn: parent; text: "E"; font.bold: true; font.pixelSize: 18; color: root.colors.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Label { text: "Capture Console"; font.pixelSize: 18; font.bold: true; color: root.colors.text; Layout.fillWidth: true }
                    Label { text: "Edge workspace"; font.pixelSize: 12; color: root.colors.muted; Layout.fillWidth: true }
                }
                StatusPill {
                    label: root.streamEdgeAvailable ? "Camera connected" : "Camera offline"
                    dotColor: root.streamEdgeAvailable ? "#23815c" : root.colors.danger
                }
                Label {
                    text: root.currentUser.full_name || ""
                    color: root.colors.muted
                    Layout.maximumWidth: 180
                    elide: Text.ElideRight
                }
                ToolButton {
                    text: "↻"; font.pixelSize: 23
                    Layout.preferredWidth: 34; Layout.maximumWidth: 34
                    enabled: root.token.length > 0 && !root.busy
                    ToolTip.visible: hovered
                    ToolTip.text: "Refresh data"
                    Accessible.name: "Refresh data"
                    onClicked: root.refreshAll(false)
                }
                ToolButton {
                    text: "↪"; font.pixelSize: 23
                    Layout.preferredWidth: 34; Layout.maximumWidth: 34
                    visible: root.token.length > 0
                    ToolTip.visible: hovered
                    ToolTip.text: "Sign out"
                    Accessible.name: "Sign out"
                    onClicked: root.logout(true)
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.border }
        }
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.token.length > 0 ? dashboardComponent : authComponent
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 34; color: root.colors.background
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28
                Label { text: "Diploma / Edge"; color: root.colors.muted; font.pixelSize: 11; Layout.fillWidth: true }
                Label { text: root.selectedDeviceId; color: root.colors.muted; font.pixelSize: 11 }
            }
        }
    }

    Component {
        id: authComponent
        Rectangle {
            color: root.colors.background

            ColumnLayout {
                width: Math.min(parent.width - 48, 460)
                anchors.centerIn: parent
                spacing: 14

                Label {
                    text: "Edge Login"
                    color: root.colors.text
                    font.pixelSize: 24
                    font.bold: true
                    Layout.fillWidth: true
                }
                Label {
                    text: "Edge workspace"
                    color: root.colors.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    ActionButton {
                        kind: root.mode === "login" ? "primary" : "secondary"
                        text: "Login"
                        checkable: true
                        checked: root.mode === "login"
                        Layout.fillWidth: true
                        onClicked: root.mode = "login"
                    }
                    ActionButton {
                        kind: root.mode === "register" ? "primary" : "secondary"
                        text: "Register"
                        checkable: true
                        checked: root.mode === "register"
                        Layout.fillWidth: true
                        onClicked: root.mode = "register"
                    }
                }

                InputField {
                    visible: root.mode === "register"
                    placeholderText: "Full name"
                    text: root.fullName
                    onTextChanged: root.fullName = text
                    Layout.fillWidth: true
                }
                InputField {
                    placeholderText: "Email"
                    text: root.email
                    onTextChanged: root.email = text
                    Layout.fillWidth: true
                }
                InputField {
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    text: root.password
                    onTextChanged: root.password = text
                    Layout.fillWidth: true
                    Keys.onReturnPressed: root.loginOrRegister()
                }
                InputField {
                    placeholderText: "Backend URL"
                    text: root.apiBaseUrl
                    onEditingFinished: {
                        root.apiBaseUrl = text
                        settings.apiBaseUrl = text
                    }
                    Layout.fillWidth: true
                }
                ActionButton {
                    kind: "primary"
                    text: root.busy ? "Working..." : (root.mode === "register" ? "Create account" : "Enter console")
                    enabled: !root.busy
                    Layout.fillWidth: true
                    onClicked: root.loginOrRegister()
                }
                StatusBanner {
                    text: root.statusText
                    kind: root.statusKind
                    Layout.fillWidth: true
                }
            }
        }
    }

    Component {
        id: dashboardComponent
        ColumnLayout {
            spacing: 0
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; color: root.colors.surface
                RowLayout {
                    anchors.left: parent.left; anchors.leftMargin: 28; height: parent.height; spacing: 26
                    Repeater {
                        model: ["Live", "Recordings", "Activity", "Devices"]
                        delegate: Button {
                            required property int index
                            required property string modelData
                            text: modelData
                            implicitHeight: 52
                            leftPadding: 0; rightPadding: 0
                            contentItem: Label { text: parent.text; color: root.workspaceIndex === index ? root.colors.accent : root.colors.muted; font.bold: root.workspaceIndex === index; verticalAlignment: Text.AlignVCenter }
                            background: Item {
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: root.colors.accent; visible: root.workspaceIndex === index }
                            }
                            onClicked: root.workspaceIndex = index
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.border; z: -1 }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.margins: 28
                spacing: 20
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Label { text: root.workspaceIndex === 0 ? "MONITOR" : "WORKSPACE"; font.pixelSize: 10; color: root.colors.muted; font.bold: true }
                        Label { text: ["Live stream", "Recordings", "Activity", "Devices"][root.workspaceIndex]; font.pixelSize: 25; color: root.colors.text; font.bold: true }
                    }
                    StatusPill {
                        visible: root.workspaceIndex === 0
                        label: root.streamEdgeRecording ? "Recording" : root.streamEdgeStreaming ? "Live" : "Idle"
                        dotColor: root.streamEdgeRecording ? root.colors.danger : root.streamEdgeStreaming ? "#23815c" : root.colors.muted
                    }
                }
                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: root.workspaceIndex
                    RowLayout {
                        spacing: 28
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Layout.minimumHeight: 240
                              Rectangle {
                                id: liveSurface
                                anchors.fill: parent
                                radius: 5; color: root.colors.dark; clip: true
                                states: State {
                                    name: "fullscreen"
                                    when: root.fullscreenTarget === "live"
                                    ParentChange {
                                        target: liveSurface
                                        parent: fullscreenHost
                                    }
                                }
                                VideoPreviewItem {
                                    id: localPreview
                                    objectName: "cameraPreview"
                                    sourcePipeline: root.previewPipeline
                                    anchors.fill: parent
                                    visible: root.streamEdgeStreaming
                                }
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 40, 440)
                                    spacing: 10
                                    visible: !root.streamEdgeStreaming || !localPreview.liveFrameActive
                                    Label {
                                        text: root.streamEdgeStreaming ? "Connecting camera" : "Stream offline"
                                        color: "#e6e8eb"; font.pixelSize: 19; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true
                                    }
                                    Label {
                                        text: root.streamEdgeAvailable ? "Camera standing by" : "Camera service unavailable"
                                        color: "#9198a4"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                }
                                Label {
                                    visible: root.streamEdgeStreaming && localPreview.liveFrameActive
                                    anchors.left: parent.left; anchors.leftMargin: 60
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                                    text: "●  LIVE"; color: "#b9e8cf"; font.pixelSize: 11
                                    padding: 7
                                    background: Rectangle { color: "#dd22262f"; radius: 4 }
                                }
                                VideoToolButton {
                                    objectName: "liveFullscreenButton"
                                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 12
                                    text: "⛶"
                                    tooltip: root.fullscreenTarget === "live" ? "Exit fullscreen" : "Fullscreen"
                                    onClicked: root.toggleVideoFullscreen("live")
                                }
                              }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    Label {
                                        text: root.streamEdgeStreaming && root.selectedStream ? root.selectedStream.title : root.streamTitle
                                        color: root.colors.text; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight
                                    }
                                    Label { text: root.selectedDeviceId; color: root.colors.muted; font.pixelSize: 11 }
                                }
                                Label { text: "Local preview"; color: root.colors.muted; font.pixelSize: 11 }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.colors.border }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Latest activity"; color: root.colors.text; font.bold: true; Layout.fillWidth: true }
                                Button { text: "View all"; flat: true; onClicked: root.workspaceIndex = 2 }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredHeight: 24
                                Label {
                                    text: root.latestCommand.command ? (root.latestCommand.command + " " + root.latestCommand.target) : "No activity yet"
                                    color: root.colors.muted; Layout.fillWidth: true; elide: Text.ElideRight
                                }
                                Label { text: root.latestCommand.status || ""; color: root.statusColor(root.latestCommand.status); font.pixelSize: 12 }
                            }
                        }
                        Rectangle { Layout.fillHeight: true; width: 1; color: root.colors.border }
                        ScrollView {
                            id: captureScroll
                            Layout.preferredWidth: 252; Layout.minimumWidth: 252; Layout.maximumWidth: 252; Layout.fillHeight: true
                            contentWidth: availableWidth
                            clip: true
                            ColumnLayout {
                            width: captureScroll.availableWidth
                            spacing: 14
                            Label { text: "Capture"; font.bold: true; color: root.colors.text }
                            LabelText { text: "Edge device" }
                            Label { text: root.selectedDeviceId; color: root.colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                            LabelText { text: "Stream name" }
                            InputField {
                                Layout.fillWidth: true; implicitHeight: 38
                                text: root.streamEdgeStreaming && root.selectedStream ? root.selectedStream.title : root.streamTitle
                                enabled: !root.streamEdgeStreaming && !root.busy
                                onEditingFinished: root.streamTitle = text
                                background: Rectangle { color: "white"; radius: 5; border.color: root.colors.border }
                            }
                            ActionButton {
                                Layout.fillWidth: true
                                text: root.hasPendingCommand() ? "Command pending" : root.streamEdgeStreaming ? "■  Stop stream" : "▶  Start stream"
                                kind: root.streamEdgeStreaming ? "danger" : "primary"
                                enabled: !root.busy && !root.hasPendingCommand() && root.streamEdgeAvailable
                                onClicked: root.streamEdgeStreaming ? root.stopCurrentStream() : root.startCurrentStream()
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.colors.border; Layout.topMargin: 6; Layout.bottomMargin: 6 }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Recording"; font.bold: true; color: root.colors.text; Layout.fillWidth: true }
                                Label { text: root.streamEdgeRecording ? "Recording" : "Off"; color: root.streamEdgeRecording ? root.colors.danger : root.colors.muted; font.pixelSize: 11 }
                            }
                            ActionButton {
                                Layout.fillWidth: true
                                text: root.streamEdgeRecording ? "■  Stop recording" : "●  Start recording"
                                kind: root.streamEdgeRecording ? "danger" : "secondary"
                                enabled: !root.busy && !root.hasPendingCommand() && root.streamEdgeStreaming && root.selectedStreamId.length > 0 && root.selectedStream && root.selectedStream.user_id === root.currentUser.id
                                onClicked: root.streamEdgeRecording ? root.stopCurrentRecording() : root.startCurrentRecording()
                            }
                            Item { Layout.preferredHeight: 4 }
                            MetricRow { label: "Backend"; value: root.syncConnected ? "Connected" : "Unavailable" }
                            MetricRow { label: "Last update"; value: root.lastRefreshText }
                            StatusBanner {
                                Layout.fillWidth: true
                                visible: root.statusText !== "Ready" && root.statusText.length > 0
                                text: root.statusText; kind: root.statusKind
                            }
                            }
                        }
                    }
                    Item {
                        ListView {
                            anchors.fill: parent; clip: true; spacing: 0; model: root.videos
                            ScrollBar.vertical: ScrollBar {}
                            delegate: ListRow {
                                titleText: modelData.title || "Untitled recording"
                                metaText: (modelData.status || "") + " · " + (modelData.duration_seconds || 0) + " sec · " + new Date(modelData.created_at).toLocaleString()
                                statusText: modelData.status || ""
                                actionIcon: ["completed", "uploading"].indexOf(modelData.status) >= 0 ? "▶" : ""
                                onClicked: root.openRecording(modelData)
                            }
                            Label { anchors.centerIn: parent; visible: root.videos.length === 0; text: "No recordings yet"; color: root.colors.muted }
                        }
                    }
                    Item {
                        ListView {
                            anchors.fill: parent; clip: true; spacing: 0; model: root.commands
                            ScrollBar.vertical: ScrollBar {}
                            delegate: ListRow {
                                titleText: (modelData.command || "") + " " + (modelData.target || "")
                                metaText: (modelData.status || "") + " · " + (modelData.error_message || new Date(modelData.created_at).toLocaleString())
                                statusText: modelData.status || ""
                            }
                            Label { anchors.centerIn: parent; visible: root.commands.length === 0; text: "No commands yet"; color: root.colors.muted }
                        }
                    }
                    ColumnLayout {
                        spacing: 22
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            InputField {
                                Layout.preferredWidth: 280; implicitHeight: 40
                                text: root.selectedDeviceId
                                placeholderText: "Device ID"
                                onEditingFinished: { root.selectedDeviceId = text; settings.deviceId = text }
                            }
                            ActionButton { text: "Register device"; enabled: !root.busy; onClicked: root.registerCurrentDevice() }
                            Item { Layout.fillWidth: true }
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: root.devices
                            ScrollBar.vertical: ScrollBar {}
                            delegate: ListRow {
                                titleText: modelData.name || modelData.id
                                metaText: (modelData.status || "") + " · Stream " + (modelData.streaming ? "live" : "off") + " · Recording " + (modelData.recording ? "on" : "off")
                                statusText: modelData.status || ""
                                selected: root.selectedDeviceId === modelData.id
                                onClicked: { root.selectedDeviceId = modelData.id; settings.deviceId = modelData.id }
                            }
                        }
                    }
                }
            }
        }
    }

    component InputField: TextField {
        implicitHeight: 40
        leftPadding: 12
        rightPadding: 12
        color: root.colors.text
        background: Rectangle { color: "white"; radius: 5; border.color: parent.activeFocus ? root.colors.accent : root.colors.border }
    }

    component VideoToolButton: Button {
        property string tooltip: ""
        width: 36; height: 36
        implicitWidth: 36; implicitHeight: 36
        padding: 0
        hoverEnabled: true
        ToolTip.visible: hovered
        ToolTip.text: tooltip
        ToolTip.delay: 400
        Accessible.name: tooltip
        contentItem: Label {
            text: parent.text
            color: "white"
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: parent.hovered ? "#454a54" : "#dd22262f"
            border.color: "#454a54"
            radius: 4
        }
    }

    component ActionButton: Button {
        property string kind: "secondary"
        implicitHeight: 40
        leftPadding: 12; rightPadding: 12
        opacity: enabled ? 1 : 0.45
        contentItem: Label {
            text: parent.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            font.pixelSize: 12; font.bold: true
            color: parent.kind === "primary" ? "white" : parent.kind === "danger" ? root.colors.danger : root.colors.text
        }
        background: Rectangle {
            radius: 5
            color: parent.kind === "primary" ? (parent.hovered ? "#194cc7" : root.colors.accent) : parent.kind === "danger" ? "#fff4f5" : (parent.hovered ? root.colors.surfaceAlt : "white")
            border.color: parent.activeFocus ? root.colors.accent : parent.kind === "primary" ? root.colors.accent : root.colors.border
        }
    }

    component Panel: Rectangle {
        property string title: ""
        color: root.colors.surface
        radius: 8
        border.color: root.colors.border
        clip: true

        Label {
            x: 16
            y: 15
            text: parent.title
            font.pixelSize: 17
            font.bold: true
            color: root.colors.text
        }
    }

    component LabelText: Label {
        color: root.colors.muted
        font.pixelSize: 12
        font.bold: true
    }

    component StatusPill: Rectangle {
        Layout.fillWidth: false
        property string label: ""
        property color dotColor: root.colors.muted
        implicitHeight: 34
        implicitWidth: labelText.implicitWidth + 38
        radius: 0
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 12
            spacing: 7
            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: dotColor
            }
            Label {
                id: labelText
                text: parent.parent.label
                color: root.colors.text
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    component StatusBanner: Rectangle {
        property string text: ""
        property string kind: "info"
        implicitHeight: Math.max(42, bannerLabel.implicitHeight + 18)
        radius: 8
        color: kind === "error" ? "#fff1f0" : kind === "success" ? root.colors.accentSoft : root.colors.surfaceAlt
        border.color: kind === "error" ? "#ffc9c4" : kind === "success" ? "#c9d8f5" : root.colors.border

        Label {
            id: bannerLabel
            anchors.fill: parent
            anchors.margins: 9
            text: parent.text
            color: parent.kind === "error" ? root.colors.danger : parent.kind === "success" ? root.colors.accent : root.colors.muted
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    component MetricRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        Label {
            text: parent.label
            color: root.colors.muted
            Layout.fillWidth: true
        }
        Label {
            text: parent.value
            color: root.colors.text
            font.bold: true
        }
    }

    component ListRow: Rectangle {
        property string titleText: ""
        property string metaText: ""
        property string statusText: ""
        property bool selected: false
        property string actionIcon: ""
        signal clicked()

        width: ListView.view ? ListView.view.width : 260
        height: 64
        radius: 0
        color: selected ? root.colors.accentSoft : "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.border }

        MouseArea {
            anchors.fill: parent
            cursorShape: parent.actionIcon.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9

            Rectangle {
                width: 9
                height: 9
                radius: 5
                color: root.statusColor(parent.parent.statusText)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label {
                    text: titleText
                    color: root.colors.text
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: metaText
                    color: root.colors.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Label {
                text: actionIcon
                visible: actionIcon.length > 0
                color: root.colors.accent
                font.pixelSize: 18
            }
        }
    }
}
