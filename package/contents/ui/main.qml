import QtQuick 2.5
import QtQuick.Layouts 1.1
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponent

Item {
	id: root

	Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
	Plasmoid.compactRepresentation: CompactRepresentation {}
	Plasmoid.fullRepresentation: FullRepresentation {}

	Plasmoid.status: {
        if (updatesCount > 0 || statusCheck || statusError) {
            return PlasmaCore.Types.ActiveStatus
        }
        return PlasmaCore.Types.PassiveStatus
	}

	property var listModel: updatesListModel
	property var updatesList
	property var updatesCount

	property bool statusCheck: false
	property bool statusError: false
	property var errorCode
	property var errorText
    property string checkUpdatesCmd

	readonly property int interval: plasmoid.configuration.interval * 60000
	readonly property int wrapper: plasmoid.configuration.wrapper
	readonly property int flatpak: plasmoid.configuration.flatpak

	PlasmaCore.DataSource {
		id: sh
		engine: "executable"
		connectedSources: []
		onNewData: {
			var exitCode = data["exit code"]
			var exitStatus = data["exit status"]
			var stdout = data["stdout"]
			var stderr = data["stderr"]
			exited(sourceName, exitCode, exitStatus, stdout, stderr)
			disconnectSource(sourceName)
		}
		function exec(cmd) {
			connectSource(cmd)
		}
		signal exited(string cmd, int exitCode, int exitStatus, string stdout, string stderr)
	}

	Connections {
		target: sh
		function onExited(cmd, exitCode, exitStatus, stdout, stderr) {
			if (cmd === checkUpdatesCmd) {
				if (stderr) {
					statusError = true
					errorCode = exitCode
					errorText = stderr.split("\n")
				}
				if (stdout) {
					statusError = false
					updatesList = stdout.replace(/\n$/, '').replace(/ ->/g, "").split("\n")
					updatesCount = updatesList.length
					for (var i = 0; i < updatesCount; i++) {
						updatesListModel.append({"text": updatesList[i]})
					}
				}
				if (!stdout && !stderr) {
					statusError = false
					updatesCount = 0
				}

				statusCheck = false
			}
		}
	}

	Timer {
		id: timer
		interval: root.interval
		running: true
		repeat: true
		onTriggered: checkUpdates()
		Component.onCompleted: triggered()
	}
	
	onIntervalChanged: {
		timer.restart()
	}

	onWrapperChanged: {
		checkUpdates()
	}

	onFlatpakChanged: {
		checkUpdates()
	}

	ListModel {
        id: updatesListModel
    }

	function checkUpdates() {
		console.log(`Apdatifier -> exec -> checkUpdates() (${new Date().toLocaleTimeString().slice(0, -4)})`)
		timer.restart()
		updatesListModel.clear()
		statusError = false
		statusCheck = true
		updatesCount = ''

		if (wrapper) {
			checkUpdatesCmd = '$(command -v yay || command -v paru || command -v picaur) -Qu'
		} else {
			checkUpdatesCmd = '$(command -v checkupdates) || $(command -v pacman) -Qu'
		}
		
		if (flatpak) {
			let checkFlatpakCmd = `upd=$(flatpak remote-ls --columns=name,application,version --app --updates | \
									sed 's/ /-/g' | sed 's/\t/ /g')
									while IFS= read -r app; do
										id=$(echo "$app" | awk '{print $2}')
										ver=$(flatpak info "$id" | grep "Version:" | awk '{print $2}')
										output+="$(echo "$app" | sed "s/$id/$ver/" | tr '[:upper:]' '[:lower:]')"$'\n'
									done <<< "$upd"
									echo -en "$output"`;

			checkUpdatesCmd = `${checkUpdatesCmd} && ${checkFlatpakCmd}`
		}
			
		sh.exec(checkUpdatesCmd)
	}
}
