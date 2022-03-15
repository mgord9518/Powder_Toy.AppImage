#!/bin/sh

# Goal is to make a script to create AppImages for applications packed into a
# tarball or zip with minimal modification per app

# Variables
[ -z "$TMPDIR" ] && TMPDIR='/tmp'
[ -z "$ARCH" ]   && ARCH=$(uname -m)

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

appStream='<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop">
  <id>uk.co.powdertoy.tpt</id>
  
  <name>Powder Toy</name>
  <summary>Physics sandbox game</summary>
  
  <metadata_license>FSFAP</metadata_license>
  <project_license>GPL3</project_license>
  
  <description>
    <p>
Have you ever wanted to blow something up? Or maybe you always dreamt of operating an atomic power plant? Do you have a will to develop your own CPU? The Powder Toy lets you to do all of these, and even more!

The Powder Toy is a free physics sandbox game, which simulates air pressure and velocity, heat, gravity and a countless number of interactions between different substances! The game provides you with various building materials, liquids, gases and electronic components which can be used to construct complex machines, guns, bombs, realistic terrains and almost anything else. You can then mine them and watch cool explosions, add intricate wirings, play with little stickmen or operate your machine. You can browse and play thousands of different saves made by the community or upload your own – we welcome your creations!
    </p>
  </description>
  
  <categories>
    <category>Game</category>
    <category>Simulation</category>
  </categories>
  
  <provides>
    <binary>powder</binary>
  </provides>
</component>'

printErr() {
	echo -e "FATAL: $@"
	echo 'Log:'
	cat "$tempDir/out.log"
	rm "$tempDir/out.log"
	exit 1
}

# Create and move to working directory
mkdir -p "$tempDir/AppDir/usr/bin" \
         "$tempDir/AppDir/usr/share/icons/hicolor/scalable/apps" \
         "$tempDir/AppDir/usr/share/metainfo"

if [ ! $? = 0  ]; then
	printErr 'Failed to create temporary directory.'
fi

cd "$tempDir"
echo "Working directory: $tempDir"

# Download source and build
git clone https://github.com/The-Powder-Toy/The-Powder-Toy
cd The-Powder-Toy

echo "$appStream" > "AppDir/usr/share/metainfo/$appId.appdata.xml"

meson -Dcpp_link_args="-Wl,--no-undefined /usr/lib/$ARCH-linux-gnu/libXdmcp.a /usr/lib/$ARCH-linux-gnu/libXau.a /usr/lib/$ARCH-linux-gnu/libxcb.a" -Dbuildtype=release -Dstatic=system -Db_vscrt=static_from_buildtype \
    -Dignore_updates=true -D install_check=false build-release-static
cd build-release-static
ninja
strip -s powder
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
