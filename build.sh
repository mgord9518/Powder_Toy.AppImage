#!/bin/sh

# Goal is to make a script to create AppImages for applications packed into a
# tarball or zip with minimal modification per app

# Variables
[ -z "$TMPDIR" ] && TMPDIR='/tmp'
[ -z "$ARCH" ]   && ARCH=$(uname -m)

if [ $GITHUB_ACTIONS ]; then
	sudo apt install bsdtar
fi

aiVersion=$(curl -s https://powdertoy.co.uk | grep 'Version' | head -n 1 | tr -dc '0-9.')
# ^ Hacky one liner to parse version number from download on website. This may
# break in the future if the website is redesigned
appId='uk.co.powdertoy.tpt'
appName="Powder Toy"
appImageName=$(echo $appName | tr ' ' '_')"-$aiVersion-$ARCH.AppImage"
appBinName="powder"
tempDir="$TMPDIR/.buildApp_$appName.$RANDOM"
startDir="$PWD"
appUrl='https://powdertoy.co.uk/Download/powder-lin64.zip'
iconUrl='https://raw.githubusercontent.com/mgord9518/Powder_Toy.AppImage/main/resources/uk.co.powdertoy.tpt.svg'
comp='gzip'

# Define what should be in the desktop entry
entry="[Desktop Entry]
Version=1.0
Type=Application
Name=$appName
Comment=Physics sandbox game
Exec=$appBinName
Icon=$appId
Terminal=false
Categories=Game;Simulation;
StartupWMClass=$appBinName
X-AppImage-Version=
[X-App Permissions]
Level=3
Devices=dri;
Sockets=x11;network;"

appStream='
'

printErr() {
	echo -e "FATAL: $@"
	echo 'Log:'
	cat "$tempDir/out.log"
	rm "$tempDir/out.log"
	exit 1
}

# Create and move to working directory
mkdir -p "$tempDir/AppDir/usr/bin" \
         "$tempDir/AppDir/usr/share/icons/hicolor/scalable/apps"

if [ ! $? = 0  ]; then
	printErr 'Failed to create temporary directory.'
fi

cd "$tempDir"
echo "Working directory: $tempDir"

# Download and extract the latest zip
# Unfortunately requires BSDTAR couldn't get unzip working with stdin
# any alternative solutions welcome
#echo "Downloading and extracting $appName..."
#wget "$appUrl" -O - 2> "$tempDir/out.log" | bsdtar -Oxf - "$appBinName" > "AppDir/usr/bin/$appBinName"
#if [ ! $? = 0 ]; then
#	printErr "Failed to download '$appName' (make sure you're connected to the internet)"
#fi
#chmod +x "AppDir/usr/bin/$appBinName"

git clone https://github.com/The-Powder-Toy/The-Powder-Toy
cd The-Powder-Toy

meson -Dbuildtype=release -Dstatic=prebuilt -Db_vscrt=static_from_buildtype \
    -Dignore_updates=true -D install_check=false build-release-static
cd build-release-static
ninja
cd ../..

mv The-Powder-Toy/build-release-static/powder "AppDir/usr/bin/$appBinName"

# Download the icon
wget "$iconUrl" -O "AppDir/usr/share/icons/hicolor/scalable/apps/$appId.svg" &> "$tempDir/out.log"
if [ ! $? = 0 ]; then
	printErr "Failed to download '$appId.svg' (make sure you're connected to the internet)"
fi

# Create desktop entry and link up executable and icons
echo "$entry" > "AppDir/$appId.desktop"
ln -s "./usr/bin/$appBinName" 'AppDir/AppRun'
ln -s "./usr/share/icons/hicolor/scalable/apps/$appId.svg" "AppDir/$appId.svg"

# Check if user has AppImageTool (under the names of `appimagetool.AppImage`
# and `appimagetool-x86_64.AppImage`) if not, download it
echo 'Checking if AppImageTool is installed...'
if command -v 'mkappimage.AppImage'; then
	aitool() {
		'mkappimage.AppImage' "$@"
	}
elif command -v "mkappimage-$ARCH.AppImage"; then
	aitool() {
		"mkappimage-$ARCH.AppImage" "$@"
	}
elif command -v "$PWD/mkappimage"; then
	aitool() {
		"$PWD/mkappimage" "$@"
	}
elif command -v 'mkappimage'; then
	aitool() {
		'mkappimage' "$@"
	}
elif command -v 'appimagetool'; then
	aitool() {
		'appimagetool' "$@"
	}
else
	# Hacky one-liner to get the URL to download the latest mkappimage
	mkAppImageUrl=$(curl -q https://api.github.com/repos/probonopd/go-appimage/releases | grep $(uname -m) | grep mkappimage | grep browser_download_url | cut -d'"' -f4 | head -n1)
	echo 'Downloading `mkappimage`'
	wget "$mkAppImageUrl" -O 'mkappimage'
	chmod +x 'mkappimage'
	aitool() {
		"$PWD/mkappimage" "$@"
    }
fi


# Use the found mkappimage command to build our AppImage with update information
echo "Building $appImageName..."
export ARCH="$ARCH"
export VERSION="$aiVersion"

aitool --comp="$comp" -u \
	"gh-releases-zsync|mgord9518|Powder_Toy.AppImage|continuous|Powder_Toy-*$ARCH.AppImage.zsync" \
	'AppDir/'

if [ ! $? = 0 ]; then
	printErr "failed to build '$appImageName'"
fi

# Take the newly created AppImage and move it into the starting directory
if [ -f "$startDir/$appImageName" ]; then
	echo 'AppImage already exists; overwriting...'
	rm "$startDir/$appImageName"
fi

# Move completed AppImage and zsync file to start directory
mv $(echo $appName | tr ' ' '_')*"-$ARCH.AppImage" "$startDir"
mv $(echo $appName | tr ' ' '_')*"-$ARCH.AppImage.zsync" "$startDir"

# Remove all temporary files
echo 'Cleaning up...'
rm -rf "$tempDir"

echo 'DONE!'
