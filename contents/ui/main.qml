import QtQuick 2.0
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0

Item {
    id: root

    // Path to the pkexec command-line tool
    property string pkexecPath: "/usr/bin/pkexec"

    // Path to the conservation mode configuration file
    property string conservationModeConfigPath

    // Icons for different status: "on," "off," and "error"
    property var icons: ({
        "on": Qt.resolvedUrl("./image/on.png"),
        "off": Qt.resolvedUrl("./image/off.png"),
        "error": Qt.resolvedUrl("./image/error.png")
    })

    // The current status of the conservation mode ("on" or "off")
    property string currentStatus: "off"

    // A flag indicating whether the widget is compatible with the system
    property bool isCompatible: false

    // The notification tool to use (e.g., "zenity" or "notify-send")
    property string notificationTool: ""

    // The desired status for the conservation mode ("on" or "off")
    property string desiredStatus: "off"

    // A flag indicating if an operation is in progress
    property bool loading: false

    // The currently displayed icon
    property string icon: root.icons[root.currentStatus]

    // Set the icon for the Plasmoid
    Plasmoid.icon: root.icon

    // Executed when the component is fully initialized
    Component.onCompleted: {
        findNotificationTool()
        findConservationModeConfigFile()
    }

    // CustomDataSource for querying the current status
    CustomDataSource {
        id: queryStatusDataSource
        command: "cat " + root.conservationModeConfigPath
    }

    // CustomDataSource for setting the conservation mode status
    CustomDataSource {
        id: setStatusDataSource

        // Dynamically set in switchStatus(). Set a default value to avoid errors at startup.
        property string status: "off"

        // Commands to enable or disable conservation mode
        property var cmds: {
            "on": `echo 1 | ${root.pkexecPath} tee ${root.conservationModeConfigPath} 1>/dev/null`,
            "off": `echo 0 | ${root.pkexecPath} tee ${root.conservationModeConfigPath} 1>/dev/null`
        }
        command: cmds[status]
    }

    // CustomDataSource for finding the notification tool
    CustomDataSource {
        id: findNotificationToolDataSource
        command: "find /usr -type f -executable \\( -name \"notify-send\" -o -name \"zenity\" \\)"
    }

    // CustomDataSource for finding the conservation mode configuration file
    CustomDataSource {
        id: findConservationModeConfigFileDataSource
        command: "find /sys -name \"conservation_mode\""
    }

    // CustomDataSource for sending notifications
    CustomDataSource {
        id: sendNotification

        // Dynamically set in showNotification(). Set a default value to avoid errors at startup.
        property string tool: "notify-send"

        property string iconURL: ""
        property string title: ""
        property string message: ""
        property string options: ""

        property var cmds: {
            "notify-send": `notify-send -i ${iconURL} '${title}' '${message}' ${options}`,
            "zenity": `zenity --notification --text='${title}\\n${message}'`
        }
        command: cmds[tool]
    }

    // Connection for handling the queryStatusDataSource
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

    // Connection for handling the setStatusDataSource
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

    // Connection for finding the notification tool
    Connections {
        target: findNotificationToolDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            if (stdout) {
                // Many Linux distros have two notification tools: notify-send and zenity
                var paths = stdout.trim().split("\n")
                var path1 = paths[0]
                var path2 = paths[1]

                // Prefer notify-send because it allows using an icon; zenity v3.44.0 does not accept an icon option
                if (path1 && path1.trim().endsWith("notify-send")) {
                    root.notificationTool = "notify-send"
                } else if (path2 && path2.trim().endsWith("notify-send")) {
                    root.notificationTool = "notify-send"
                } else if (path1 && path1.trim().endsWith("zenity")) {
                    root.notificationTool = "zenity"
                } else {
                    console.warn("No compatible notification tool found.")
                }
            }
        }
    }

    // Connection for finding the conservation mode configuration file
    Connections {
        target: findConservationModeConfigFileDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            if (stdout.trim()) {
                root.conservationModeConfigPath = stdout.trim()
                queryStatus()
            } else {
                root.isCompatible = false
                root.icon = root.icons.error
            }
        }
    }

    // Get the current status
    function queryStatus() {
        root.loading = true
        queryStatusDataSource.exec()
    }

    // Switch the conservation mode status
    function switchStatus() {
        root.loading = true
        showNotification(root.icons[root.desiredStatus], i18n("Switching status to %1.", root.desiredStatus.toUpperCase()))

        setStatusDataSource.status = root.desiredStatus
        setStatusDataSource.exec()
    }

    // Show a notification with an icon, message, title, and options
    function showNotification(iconURL: string, message: string, title = i18n("Conservation Mode Switcher"), options = ""){
        sendNotification.tool = root.notificationTool

        sendNotification.iconURL = iconURL
        sendNotification.title = title
        sendNotification.message = message
        sendNotification.options = options

        sendNotification.exec()
    }

    // Find the notification tool
    function findNotificationTool() {
        findNotificationToolDataSource.exec()
    }

    // Find the conservation mode configuration file
    function findConservationModeConfigFile() {
        // Check if the user defined the file path manually and use it if they did.
        if (plasmoid.configuration.conservationModeConfigFile){
            root.conservationModeConfigPath = plasmoid.configuration.conservationModeConfigFile
        } else {
            findConservationModeConfigFileDataSource.exec()
        }
    }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    Plasmoid.compactRepresentation: Item {
        PlasmaCore.IconItem {
            height: plasmoid.configuration.iconSize
            width: plasmoid.configuration.iconSize
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

            // Label displaying the current status
            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                text: root.isCompatible ? i18n("Conservation Mode is %1.", root.currentStatus.toUpperCase()) : i18n("The conservation mode is not available.")
            }

            // Switch to toggle the conservation mode status
            PlasmaComponents3.Switch {
                Layout.alignment: Qt.AlignCenter

                enabled: !root.loading && root.isCompatible
                checked: root.desiredStatus === "on"
                onCheckedChanged: {
                    root.desiredStatus = checked ? "on" : "off"
                    if (root.desiredStatus !== root.currentStatus){
                        switchStatus()
                    }
                }
            }

            // Busy indicator when an operation is in progress
            BusyIndicator {
                id: loadingIndicator
                Layout.alignment: Qt.AlignCenter
                running: root.loading
            }
        }
    }

    // Tooltip text for the Plasmoid
    Plasmoid.toolTipMainText: i18n("Switch Conservation Mode.")
    Plasmoid.toolTipSubText: root.isCompatible ? i18n("Conservation Mode is %1.", root.currentStatus.toUpperCase()) : i18n("The conservation mode is not available.")
}
