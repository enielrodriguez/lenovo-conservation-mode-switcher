import QtQuick 2.0
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0


Item {
    id: root

    property string pkexecPath: "/usr/bin/pkexec"

    property string conservationModeConfigPath

    readonly property string const_ZERO_TIMEOUT_NOTIFICATION: " -t 0"

    readonly property var const_COMMANDS: ({
        "query": "cat " + root.conservationModeConfigPath,
        "on": "echo 1 | " + root.pkexecPath + " tee " + root.conservationModeConfigPath + " 1>/dev/null",
        "off": "echo 0 | " + root.pkexecPath + " tee " + root.conservationModeConfigPath + " 1>/dev/null",
        "findConservationModeConfigFile": "find /sys -name \"conservation_mode\"",
        "findNotificationTool": "find /usr -type f -executable \\( -name \"notify-send\" -o -name \"zenity\" \\)",
        // defined in findNotificationTool Connection
        "sendNotification": () => ""
    })

    property var icons: ({
        "on": Qt.resolvedUrl("./image/on.png"),
        "off": Qt.resolvedUrl("./image/off.png"),
        "error": Qt.resolvedUrl("./image/error.png")
    })

    // This values can change after the execution of onCompleted().
    property string currentStatus: "off"
    property bool isCompatible: false

    property string desiredStatus: "off"
    property bool loading: false

    property string icon: root.icons[root.currentStatus]

    Plasmoid.icon: root.icon

    Connections {
        target: Plasmoid.configuration
    }

    Component.onCompleted: {
        findNotificationTool()
        findConservationModeConfigFile()
    }

    PlasmaCore.DataSource {
        id: queryStatusDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: setStatusDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: findNotificationToolDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            // stderr output can contain "permission denied" errors
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: findConservationModeConfigFileDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            // stderr output can contain "permission denied" errors
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: sendNotification
        engine: "executable"
        connectedSources: []

        onNewData: {
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }


    Connections {
        target: queryStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){

            if (stderr) {
                root.icon = root.icons.error
                showNotification(root.icons.error, stderr, stderr)
            } else {
                var status = stdout.trim()
                root.currentStatus = root.desiredStatus = status === "1"? "on" : "off"
                root.isCompatible = true
                root.loading = false
            }
        }
    }


    Connections {
        target: setStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            root.loading = false

            if(exitCode === 127){
                showNotification(root.icons.error, i18n("Root privileges are required."))
                root.desiredStatus = root.currentStatus
                return
            }

            if (stderr) {
                showNotification(root.icons.error, stderr, stdout)
            } else {
                root.currentStatus = root.desiredStatus
                showNotification(root.icons[root.currentStatus], i18n("Status switched to %1.", root.currentStatus.toUpperCase()))
            }
        }
    }


    Connections {
        target: findNotificationToolDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){

            if (stdout) {
                // Many Linux distros have two notification tools
                var paths = stdout.trim().split("\n")
                var path1 = paths[0]
                var path2 = paths[1]

                // prefer notify-send because it allows to use icon, zenity v3.44.0 does not accept icon option
                if (path1 && path1.trim().endsWith("notify-send")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path1.trim() + " -i " + iconURL + " '" + title + "' '" + message + "'" + options
                }if (path2 && path2.trim().endsWith("notify-send")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path2.trim() + " -i " + iconURL + " '" + title + "' '" + message + "'" + options
                }else if (path1 && path1.trim().endsWith("zenity")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path1.trim() + " --notification --text='" + title + "\\n" + message + "'"
                }
            }
        }
    }


    Connections {
        target: findConservationModeConfigFileDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            // We assume that there can only be a single conservation_mode file.
            // TODO: handle two conservation_mode files for dual battery systems (if that exists in Lenovo).

            if (stdout.trim()) {
                root.conservationModeConfigPath = stdout.trim()
                queryStatus()
            }else {
                root.isCompatible = false
                root.icon = root.icons.error
            }
        }
    }


    // Get the current status
    function queryStatus() {
        root.loading = true
        queryStatusDataSource.exec(const_COMMANDS.query)
    }


    function switchStatus() {
        root.loading = true

        showNotification(root.icons[root.desiredStatus], i18n("Switching status to %1.", root.desiredStatus.toUpperCase()))

        setStatusDataSource.exec(const_COMMANDS[root.desiredStatus])
    }

    function showNotification(iconURL: string, message: string, title = i18n("Conservation Mode Switcher"), options = const_ZERO_TIMEOUT_NOTIFICATION){
        sendNotification.exec(const_COMMANDS.sendNotification(title, message, iconURL, options))
    }

    function findNotificationTool() {
        findNotificationToolDataSource.exec(const_COMMANDS.findNotificationTool)
    }

    function findConservationModeConfigFile() {
        // Check if the user defined the file path manually and use it if he did.
        if(Plasmoid.configuration.conservationModeConfigFile){
            root.conservationModeConfigPath = Plasmoid.configuration.conservationModeConfigFile
        }else{
            findConservationModeConfigFileDataSource.exec(const_COMMANDS.findConservationModeConfigFile)
        }

    }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    Plasmoid.compactRepresentation: Item {
        PlasmaCore.IconItem {
            height: Plasmoid.configuration.iconSize
            width: Plasmoid.configuration.iconSize
            anchors.centerIn: parent

            source: root.icon
            active: compactMouse.containsMouse

            MouseArea {
                id: compactMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    plasmoid.expanded = !plasmoid.expanded
                }
            }
        }
    }

    Plasmoid.fullRepresentation: Item {
        Layout.preferredWidth: 400 * PlasmaCore.Units.devicePixelRatio
        Layout.preferredHeight: 300 * PlasmaCore.Units.devicePixelRatio

        ColumnLayout {
            anchors.centerIn: parent

            Image {
                id: mode_image
                source: root.icon
                Layout.alignment: Qt.AlignCenter
                Layout.preferredHeight: 64
                fillMode: Image.PreserveAspectFit
            }


            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                text: root.isCompatible ? i18n("Conservation Mode is %1.", root.currentStatus.toUpperCase()) : i18n("The conservation mode is not available.")
            }


            PlasmaComponents3.Switch {
                Layout.alignment: Qt.AlignCenter

                enabled: !root.loading && root.isCompatible
                checked: root.desiredStatus === "on"
                onCheckedChanged: {
                    root.desiredStatus = checked ? "on" : "off"
                    if(root.desiredStatus !== root.currentStatus){
                        switchStatus()
                    }
                }
            }

            BusyIndicator {
                id: loadingIndicator
                Layout.alignment: Qt.AlignCenter
                running: root.loading
            }

        }
    }

    Plasmoid.toolTipMainText: i18n("Switch Conservation Mode.")
    Plasmoid.toolTipSubText: root.isCompatible ? i18n("Conservation Mode is %1.", root.currentStatus.toUpperCase()) : i18n("The conservation mode is not available.")
}
