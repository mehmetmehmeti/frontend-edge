import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

ApplicationWindow {
    id: root
    width: 1280
    height: 760
    visible: true
    title: "Diploma Edge Console"
    color: "#f5f7f4"

    property string apiBaseUrl: "http://127.0.0.1:3002"
    property string defaultDeviceId: "edge-dev-001"
    property string token: settings.authToken
    property var currentUser: ({})
    property var users: []
    property var devices: []
    property var streams: []
    property var videos: []
    property var commands: []
    property string email: ""
    property string password: ""
    property string fullName: ""
    property string mode: "login"
    property string statusText: "Ready"
    property string selectedStreamId: ""
    property string deviceId: defaultDeviceId
    property string streamTitle: "Edge local stream"
    property bool busy: false

    Settings {
        id: settings
        property string authToken: ""
    }

    function request(path, method, body, callback) {
        const xhr = new XMLHttpRequest()
        xhr.open(method || "GET", root.apiBaseUrl + path)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (root.token && root.token.length > 0)
            xhr.setRequestHeader("Authorization", "Bearer " + root.token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            root.busy = false
            let payload = ({})
            try {
                payload = xhr.responseText.length > 0 ? JSON.parse(xhr.responseText) : ({})
            } catch (error) {
                payload = ({ message: xhr.responseText })
            }

            if (xhr.status < 200 || xhr.status >= 300) {
                root.statusText = payload.message || payload.error || ("Request failed: " + xhr.status)
                return
            }

            if (callback)
                callback(payload)
        }
        root.busy = true
        xhr.send(body ? JSON.stringify(body) : undefined)
    }

    function loginOrRegister() {
        const payload = root.mode === "register"
            ? ({ email: root.email, password: root.password, fullName: root.fullName, role: "OPERATOR" })
            : ({ email: root.email, password: root.password })
        root.request("/auth/" + root.mode, "POST", payload, function(response) {
            root.token = response.token || ""
            settings.authToken = root.token
            root.currentUser = response.user || ({})
            root.statusText = "Authenticated"
            root.refreshAll()
        })
    }

    function logout() {
        root.token = ""
        settings.authToken = ""
        root.currentUser = ({})
    }

    function refreshAll() {
        if (!root.token)
            return
        root.request("/auth/me", "GET", null, function(response) {
            root.currentUser = response.user || ({})
        })
        root.request("/users", "GET", null, function(response) {
            root.users = response.users || []
        })
        root.request("/devices", "GET", null, function(response) {
            root.devices = response.devices || []
        })
        root.request("/streams", "GET", null, function(response) {
            root.streams = response.streams || []
            if (!root.selectedStreamId && root.streams.length > 0)
                root.selectedStreamId = root.streams[0].id || ""
        })
        root.request("/videos", "GET", null, function(response) {
            root.videos = response.videos || []
        })
        root.request("/commands", "GET", null, function(response) {
            root.commands = response.commands || []
            root.statusText = "Data refreshed"
        })
    }

    function registerCurrentDevice() {
        root.request("/devices", "POST", {
            id: root.deviceId,
            name: root.deviceId,
            status: "online",
            source_ready: true
        }, function() {
            root.statusText = "Device registered"
            root.refreshAll()
        })
    }

    function startCurrentStream() {
        root.request("/streams/start", "POST", {
            device_id: root.deviceId,
            title: root.streamTitle
        }, function(response) {
            root.selectedStreamId = response.stream ? response.stream.id : ""
            root.statusText = "Start command queued"
            root.refreshAll()
        })
    }

    function stopCurrentStream() {
        if (!root.selectedStreamId)
            return
        root.request("/streams/" + root.selectedStreamId + "/stop", "POST", {}, function() {
            root.statusText = "Stop command queued"
            root.refreshAll()
        })
    }

    function startCurrentRecording() {
        if (!root.selectedStreamId)
            return
        root.request("/streams/" + root.selectedStreamId + "/recordings/start", "POST", {}, function() {
            root.statusText = "Recording command queued"
            root.refreshAll()
        })
    }

    function stopCurrentRecording() {
        if (!root.selectedStreamId)
            return
        root.request("/streams/" + root.selectedStreamId + "/recordings/stop", "POST", {}, function() {
            root.statusText = "Stop recording command queued"
            root.refreshAll()
        })
    }

    Timer {
        running: root.token.length > 0
        repeat: true
        interval: 2500
        onTriggered: root.refreshAll()
    }

    Component.onCompleted: {
        if (root.token.length > 0)
            root.refreshAll()
    }

    Rectangle {
        anchors.fill: parent
        color: "#f5f7f4"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "Edge Console"
                        font.pixelSize: 26
                        font.bold: true
                        color: "#17211b"
                    }
                    Label {
                        text: root.token ? ((root.currentUser.full_name || "Local operator") + " · " + root.statusText) : "Local auth and device control"
                        color: "#657166"
                    }
                }

                Button {
                    text: "Refresh"
                    enabled: root.token.length > 0 && !root.busy
                    onClicked: root.refreshAll()
                }
                Button {
                    text: "Logout"
                    visible: root.token.length > 0
                    onClicked: root.logout()
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.token.length > 0 ? dashboardComponent : authComponent
            }
        }
    }

    Component {
        id: authComponent
        Rectangle {
            color: "#ffffff"
            radius: 8
            border.color: "#d8ded4"
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: Math.min(parent.width - 48, 420)
                anchors.centerIn: parent
                spacing: 12

                RowLayout {
                    Button {
                        text: "Login"
                        checked: root.mode === "login"
                        checkable: true
                        onClicked: root.mode = "login"
                    }
                    Button {
                        text: "Register"
                        checked: root.mode === "register"
                        checkable: true
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
                }
                Button {
                    text: root.busy ? "Working..." : (root.mode === "register" ? "Create account" : "Enter console")
                    enabled: !root.busy
                    Layout.fillWidth: true
                    onClicked: root.loginOrRegister()
                }
                Label {
                    text: root.statusText
                    color: "#b42318"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    Component {
        id: dashboardComponent
        GridLayout {
            columns: 3
            columnSpacing: 16
            rowSpacing: 16

            Panel {
                title: "Device Control"
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
                    spacing: 10

                    TextField {
                        placeholderText: "Device id"
                        text: root.deviceId
                        onTextChanged: root.deviceId = text
                        Layout.fillWidth: true
                    }
                    TextField {
                        placeholderText: "Stream title"
                        text: root.streamTitle
                        onTextChanged: root.streamTitle = text
                        Layout.fillWidth: true
                    }
                    Button { text: "Register Device"; Layout.fillWidth: true; onClicked: root.registerCurrentDevice() }
                    Button { text: "Start Stream"; Layout.fillWidth: true; onClicked: root.startCurrentStream() }
                    Button { text: "Stop Stream"; Layout.fillWidth: true; onClicked: root.stopCurrentStream() }
                    Button { text: "Start Recording"; Layout.fillWidth: true; onClicked: root.startCurrentRecording() }
                    Button { text: "Stop Recording"; Layout.fillWidth: true; onClicked: root.stopCurrentRecording() }
                    Label {
                        text: root.statusText
                        color: "#657166"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Panel {
                title: "Synced Streams"
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
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
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#101613"
                        Label {
                            anchors.centerIn: parent
                            width: parent.width - 48
                            horizontalAlignment: Text.AlignHCenter
                            text: "Local preview hooks into stream-edge/Qt video item in the next slice."
                            color: "#dbe6df"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Panel {
                title: "Commands"
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
                    spacing: 8
                    model: root.commands
                    delegate: ListRow {
                        titleText: (modelData.command || "") + " " + (modelData.target || "")
                        metaText: (modelData.device_id || "") + " · " + (modelData.status || "")
                    }
                }
            }

            Panel {
                title: "Devices"
                Layout.preferredWidth: 340
                Layout.preferredHeight: 240
                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
                    spacing: 8
                    model: root.devices
                    delegate: ListRow {
                        titleText: modelData.name || modelData.id
                        metaText: (modelData.status || "") + " · stream " + (modelData.streaming ? "on" : "off")
                    }
                }
            }

            Panel {
                title: "Videos"
                Layout.fillWidth: true
                Layout.preferredHeight: 240
                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
                    spacing: 8
                    model: root.videos
                    delegate: ListRow {
                        titleText: modelData.title || modelData.id
                        metaText: (modelData.status || "") + " · " + (modelData.playback_url || "no playback url")
                    }
                }
            }

            Panel {
                title: "Users"
                Layout.preferredWidth: 320
                Layout.preferredHeight: 240
                ListView {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 48
                    spacing: 8
                    model: root.users
                    delegate: ListRow {
                        titleText: modelData.full_name || modelData.email
                        metaText: (modelData.email || "") + " · " + (modelData.role || "")
                    }
                }
            }
        }
    }

    component Panel: Rectangle {
        property string title: ""
        color: "#ffffff"
        radius: 8
        border.color: "#d8ded4"
        Label {
            x: 16
            y: 14
            text: parent.title
            font.pixelSize: 17
            font.bold: true
            color: "#17211b"
        }
    }

    component ListRow: Rectangle {
        property string titleText: ""
        property string metaText: ""
        width: ListView.view ? ListView.view.width : 260
        height: 58
        radius: 8
        color: "#fbfcfa"
        border.color: "#d8ded4"
        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 3
            Label {
                text: titleText
                color: "#17211b"
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
            }
            Label {
                text: metaText
                color: "#657166"
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
