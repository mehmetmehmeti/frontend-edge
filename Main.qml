import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

ApplicationWindow {
    id: root
    width: 1360
    height: 820
    minimumWidth: 1060
    minimumHeight: 680
    visible: true
    title: "Diploma Edge Console"
    color: root.colors.background

    readonly property var colors: appPalette

    QtObject {
        id: appPalette
        readonly property color background: "#f3f5f2"
        readonly property color surface: "#ffffff"
        readonly property color surfaceAlt: "#eef2ed"
        readonly property color text: "#17211b"
        readonly property color muted: "#657166"
        readonly property color border: "#d8ded4"
        readonly property color accent: "#0f766e"
        readonly property color accentSoft: "#e5f3f0"
        readonly property color blue: "#2563eb"
        readonly property color warning: "#a16207"
        readonly property color danger: "#b42318"
        readonly property color dark: "#101613"
    }

    Settings {
        id: settings
        property string authToken: ""
        property string apiBaseUrl: "http://127.0.0.1:3002"
        property string deviceId: "edge-dev-001"
        property string email: ""
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
    property string mode: "login"
    property string statusText: "Ready"
    property string statusKind: "info"
    property string selectedStreamId: ""
    property string selectedDeviceId: defaultDeviceId
    property string streamTitle: "Edge local stream"
    property bool busy: false
    property bool refreshing: false
    property bool syncConnected: false
    property bool streamEdgeAvailable: false
    property bool streamEdgeStreaming: false
    property bool streamEdgeRecording: false
    property string streamEdgeStatus: "unknown"
    property string streamEdgeMessage: ""
    property string lastRefreshText: "Not refreshed yet"
    property int requestCounter: 0

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
        xhr.open(method || "GET", root.apiBaseUrl.replace(/\/+$/, "") + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (root.token && root.token.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + root.token)

        if (!silent)
            root.busy = true

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (!silent && requestId === root.requestCounter)
                root.busy = false

            let payload = ({})
            try {
                payload = xhr.responseText.length > 0 ? JSON.parse(xhr.responseText) : ({})
            } catch (error) {
                payload = ({ message: xhr.responseText })
            }

            if (xhr.status < 200 || xhr.status >= 300) {
                const message = payload.message || payload.error || ("Request failed: " + xhr.status)
                root.setStatus(message, "error")
                if (xhr.status === 401)
                    root.logout(false)
                return
            }

            if (callback)
                callback(payload)
        }
        xhr.onerror = function() {
            if (!silent)
                root.busy = false
            root.setStatus("Could not reach edge backend at " + root.apiBaseUrl, "error")
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
            if ((!root.selectedStreamId || !root.findById(root.streams, root.selectedStreamId)) && root.streams.length > 0)
                root.selectedStreamId = root.streams[0].id || ""
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
            root.streamEdgeMessage = String(payload.lastError || payload.sourceSignalError || payload.message || "")
        }
        xhr.onerror = function() {
            root.streamEdgeAvailable = false
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
            return root.colors.accent
        if (normalized === "starting" || normalized === "pending" || normalized === "claimed" || normalized === "processing" || normalized === "uploading" || normalized === "recording")
            return root.colors.blue
        if (normalized === "error" || normalized === "failed" || normalized === "offline")
            return root.colors.danger
        if (normalized === "stopping" || normalized === "ended")
            return root.colors.warning
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
        anchors.margins: 18
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: "Diploma Edge Console"
                    font.pixelSize: 26
                    font.bold: true
                    color: root.colors.text
                }
                Label {
                    text: root.token
                          ? ((root.currentUser.full_name || "Local operator") + " · " + root.selectedDeviceId)
                          : "Local device control, command sync, and recording operations"
                    color: root.colors.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            StatusPill {
                label: root.streamEdgeAvailable ? (root.streamEdgeStreaming ? "Stream-edge live" : "Stream-edge ready") : "Stream-edge offline"
                dotColor: root.streamEdgeAvailable ? root.colors.accent : root.colors.danger
            }
            StatusPill {
                label: root.syncConnected ? "Backend synced" : "Backend waiting"
                dotColor: root.syncConnected ? root.colors.accent : root.colors.warning
            }
            ToolButton {
                text: "Refresh"
                enabled: root.token.length > 0 && !root.busy
                onClicked: root.refreshAll(false)
            }
            ToolButton {
                text: "Logout"
                visible: root.token.length > 0
                onClicked: root.logout(true)
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.token.length > 0 ? dashboardComponent : authComponent
        }
    }

    Component {
        id: authComponent
        Rectangle {
            color: root.colors.surface
            radius: 8
            border.color: root.colors.border

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
                    text: "Use local credentials stored on the edge backend."
                    color: root.colors.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Button {
                        text: "Login"
                        checkable: true
                        checked: root.mode === "login"
                        Layout.fillWidth: true
                        onClicked: root.mode = "login"
                    }
                    Button {
                        text: "Register"
                        checkable: true
                        checked: root.mode === "register"
                        Layout.fillWidth: true
                        onClicked: root.mode = "register"
                    }
                }

                TextField {
                    visible: root.mode === "register"
                    placeholderText: "Full name"
                    text: root.fullName
                    onTextChanged: root.fullName = text
                    Layout.fillWidth: true
                }
                TextField {
                    placeholderText: "Email"
                    text: root.email
                    onTextChanged: root.email = text
                    Layout.fillWidth: true
                }
                TextField {
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    text: root.password
                    onTextChanged: root.password = text
                    Layout.fillWidth: true
                    Keys.onReturnPressed: root.loginOrRegister()
                }
                TextField {
                    placeholderText: "Backend URL"
                    text: root.apiBaseUrl
                    onEditingFinished: {
                        root.apiBaseUrl = text
                        settings.apiBaseUrl = text
                    }
                    Layout.fillWidth: true
                }
                Button {
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
        GridLayout {
            columns: 12
            columnSpacing: 14
            rowSpacing: 14

            Panel {
                title: "Control"
                Layout.columnSpan: 3
                Layout.rowSpan: 2
                Layout.fillHeight: true
                Layout.minimumWidth: 300

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 10

                    LabelText { text: "Device id" }
                    TextField {
                        text: root.selectedDeviceId
                        onEditingFinished: {
                            root.selectedDeviceId = text
                            settings.deviceId = text
                        }
                        Layout.fillWidth: true
                    }
                    LabelText { text: "Stream title" }
                    TextField {
                        text: root.streamTitle
                        onTextChanged: root.streamTitle = text
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: "Register"
                            Layout.fillWidth: true
                            enabled: !root.busy
                            onClicked: root.registerCurrentDevice()
                        }
                        Button {
                            text: "Start"
                            Layout.fillWidth: true
                            enabled: !root.busy
                            onClicked: root.startCurrentStream()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            text: "Stop"
                            Layout.fillWidth: true
                            enabled: !root.busy && root.selectedStreamId.length > 0
                            onClicked: root.stopCurrentStream()
                        }
                        Button {
                            text: "Record"
                            Layout.fillWidth: true
                            enabled: !root.busy && root.selectedStreamId.length > 0
                            onClicked: root.startCurrentRecording()
                        }
                    }
                    Button {
                        text: "Stop Recording"
                        Layout.fillWidth: true
                        enabled: !root.busy && root.selectedStreamId.length > 0
                        onClicked: root.stopCurrentRecording()
                    }

                    StatusBanner {
                        text: root.statusText
                        kind: root.statusKind
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: root.colors.border
                    }

                    MetricRow { label: "Live streams"; value: String(root.liveStreamCount) }
                    MetricRow { label: "Recordings"; value: String(root.recordingCount) }
                    MetricRow { label: "Commands"; value: String(root.commands.length) }
                    MetricRow { label: "Last refresh"; value: root.lastRefreshText }
                }
            }

            Panel {
                title: "Local Stream Preview"
                Layout.columnSpan: 6
                Layout.rowSpan: 2
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                text: root.selectedStream ? (root.selectedStream.title || root.selectedStream.id) : "No stream selected"
                                color: root.colors.text
                                font.pixelSize: 18
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: root.selectedStream
                                      ? ((root.selectedStream.device_id || "") + " · " + (root.selectedStream.status || "unknown"))
                                      : "Start or select a stream to inspect edge state."
                                color: root.colors.muted
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        StatusPill {
                            label: root.streamEdgeStatus
                            dotColor: root.statusColor(root.streamEdgeStatus)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: root.colors.dark

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 48, 520)
                            spacing: 10
                            Label {
                                text: root.streamEdgeStreaming ? "Streaming active" : "Preview standby"
                                color: "#dbe6df"
                                font.pixelSize: 24
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                            }
                            Label {
                                text: root.streamEdgeAvailable
                                      ? (root.streamEdgeMessage.length > 0 ? root.streamEdgeMessage : "Qt video surface can attach to stream-edge frame bridge in the next slice.")
                                      : "Start stream-edge to enable local preview and stream health."
                                color: "#b9c6bf"
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Panel {
                title: "Command Queue"
                Layout.columnSpan: 3
                Layout.rowSpan: 2
                Layout.fillHeight: true
                Layout.minimumWidth: 300

                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 8
                    clip: true
                    model: root.commands.slice(0, 12)
                    delegate: ListRow {
                        titleText: (modelData.command || "") + " " + (modelData.target || "")
                        metaText: (modelData.device_id || "") + " · " + (modelData.status || "")
                        statusText: modelData.status || ""
                    }
                }
            }

            Panel {
                title: "Streams"
                Layout.columnSpan: 5
                Layout.fillWidth: true
                Layout.preferredHeight: 260

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 8

                    ComboBox {
                        Layout.fillWidth: true
                        textRole: "label"
                        valueRole: "value"
                        model: root.streams.map(function(item) {
                            return { label: (item.title || item.id) + " · " + item.status, value: item.id }
                        })
                        onActivated: root.selectedStreamId = currentValue
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: root.streams
                        delegate: ListRow {
                            titleText: modelData.title || modelData.id
                            metaText: (modelData.status || "") + " · media " + (modelData.mediasoup_stream_id || modelData.id || "")
                            statusText: modelData.status || ""
                            selected: root.selectedStreamId === modelData.id
                            onClicked: root.selectedStreamId = modelData.id || ""
                        }
                    }
                }
            }

            Panel {
                title: "Devices"
                Layout.columnSpan: 3
                Layout.fillWidth: true
                Layout.preferredHeight: 260

                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 8
                    clip: true
                    model: root.devices
                    delegate: ListRow {
                        titleText: modelData.name || modelData.id
                        metaText: (modelData.status || "") + " · stream " + (modelData.streaming ? "on" : "off") + " · rec " + (modelData.recording ? "on" : "off")
                        statusText: modelData.status || ""
                        selected: root.selectedDeviceId === modelData.id
                        onClicked: root.selectedDeviceId = modelData.id || root.selectedDeviceId
                    }
                }
            }

            Panel {
                title: "Videos"
                Layout.columnSpan: 4
                Layout.fillWidth: true
                Layout.preferredHeight: 260

                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 52
                    spacing: 8
                    clip: true
                    model: root.videos
                    delegate: ListRow {
                        titleText: modelData.title || modelData.id
                        metaText: (modelData.status || "") + " · " + (modelData.edge_local_path || modelData.playback_url || "waiting for file")
                        statusText: modelData.status || ""
                    }
                }
            }
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
        property string label: ""
        property color dotColor: root.colors.muted
        implicitHeight: 34
        implicitWidth: labelText.implicitWidth + 38
        radius: 17
        color: root.colors.surface
        border.color: root.colors.border

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
        border.color: kind === "error" ? "#ffc9c4" : kind === "success" ? "#bfddd8" : root.colors.border

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
        signal clicked()

        width: ListView.view ? ListView.view.width : 260
        height: 64
        radius: 8
        color: selected ? root.colors.accentSoft : "#fbfcfa"
        border.color: selected ? "#bfddd8" : root.colors.border

        MouseArea {
            anchors.fill: parent
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
        }
    }
}
