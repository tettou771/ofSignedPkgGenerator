#!/bin/bash

cd $(dirname "$0")

function usage {
	cat << EOM
Please write your information in "config" first.	

Usage: $(basename "$0") [OPTION]...
	* is necessory parametor
	& is necessory if you didnt confirm config yet
	
	-h	help
&	-a value		your Apple ID
*	-n value		app path
&	-p value		app specifired password
	-t value		title of installer
*	-i value		identifier (ex. com.example.appname)
*	-v value		version (ex. 1.0.0)
&	-d value		Developer ID Application (ex "Developer ID Installer: <Your Name> (XXXXXXXXXX)" ) 
&	-e value		Developer ID Installer (ex "Developer ID Installer: <Your Name> (XXXXXXXXXX)" )
	
	for example
	$(basename "$0") -a "YourAppleID" -n "emptyExample" -p "xxxx-xxxx-xxxx-xxxx" -t "Empty Example" -i "com.example.emptyExample" -v "1.0.0" -da "Developer ID Installer: <Your Name> (XXXXXXXXXX)" -di "Developer ID Installer: <Your Name> (XXXXXXXXXX)" 
EOM
}

appName=""
workingDir=""
installerTitle=""
identifier=""
version=""

# get config
if [ -e config ] ; then
	source config
	echo "Config loaded."
else
	cp config-example config
	echo "Error: No ID information. Please write your information in config first."
	exit
fi

while getopts ":a:n:p:t:i:v:d:e:h" optKey; do
	case "$optKey" in
		a)
			appleId=${OPTARG}
			echo "appleId $appleId"
			;;
		n)
			appNameWithExt=$(basename "${OPTARG}")
			appName=${appNameWithExt%\.*}
			workingDir=$(dirname "${OPTARG}")
			echo "appNameWithExt $appNameWithExt"
			echo "appName $appName"
			echo "workingDir $workingDir"
			;;
		p)
			appPass=${OPTARG}
			echo "appPass $appPass"
			;;
		t)
			installerTitle=${OPTARG}
			echo "installerTitle $installerTitle"
			;;
		i)
			identifier=${OPTARG}
			echo "identifier $identifier"
			;;
		v)
			version=${OPTARG}
			echo "version $version"
			;;
		d)
			developerIDApplication=${OPTARG}
			echo "developerIDApplication $developerIDApplication"
			;;
		e)
			developerIDInstaller=${OPTARG}
			echo "developerIDInstaller $developerIDInstaller"
			;;
		h)
			usage
			;;
	esac
done

# get app specific config
pkgconfigpath=$workingDir/pkgconfig
if [ -e $pkgconfigpath ] ; then
	source $pkgconfigpath
	echo "pkgconfig loaded."
fi

# check options
optionOk=0
if [ "$appleId" == "" ] ; then
	echo "Error no option: -a <YourAppleID> in config"
	optionOk=1
fi
if [ "$appName" == "" ] ; then
	echo "Error no option: -n <appName>"
	optionOk=1
fi
if [ "$appPass" == "" ] ; then
	echo "Error no option: -p <appPass> in config"
	optionOk=1
fi
if [ "$installerTitle" == "" ] ; then
	installerTitle="$appName"
fi
if [ "$identifier" == "" ] ; then
	echo "Error no option: -i <identifier>"
	optionOk=1
fi
if [ "$version" == "" ] ; then
	echo "Error no option: -v <version>"
	optionOk=1
fi
if [ "$developerIDApplication" == "" ] ; then
	echo "Error no option: -d <developerIDApplication> in config"
	optionOk=1
fi
if [ "$developerIDInstaller" == "" ] ; then
	echo "Error no option: -e <developerIDInstaller> in config"
	optionOk=1
fi
if [ $optionOk -eq 0 ] ;then
	echo "options ok"
else
	echo "Please confirm all options."
	exit
fi

# go workingDir
if [ "$workingDir" != "" ] ; then
	cd "$workingDir"
fi

# if app is not exist, exit
if [ ! -e "$appName.app" ] ; then
	echo "$appName.app is not founded."
	exit
fi

entitlementsPath="../$appName.entitlements"
if [ ! -e $entitlementsPath ] ; then
	entitlementsPath="../${appName}Release.entitlements"
fi
if [ ! -e $entitlementsPath ] ; then
	entitlementsPath="../${appName}Debug.entitlements"
fi
if [ ! -e $entitlementsPath ] ; then
	echo "Plist $entitlementsPath is not founded."
	echo "Please check sandbox settings."
	exit
fi

# "pkg" overwrite or exit?
if [ -e "pkg" ] ; then
	"Overwrite \"pkg\" directory ? y/N"
	read key
	if [ "$key" = "Y" -o "$key" = "y" ] ;then
		echo "Delete pkg directory."
		rm -rf pkg
	else
		echo "Exit"
		exit
	fi
fi

echo "Start make signed pkg."
mkdir pkg
mkdir pkg/Applications
cp -r $appName.app pkg/Applications/
cd pkg
entitlementsPath="../$entitlementsPath"

codesign --verify \
	--sign "$developerIDApplication" \
	--deep \
	--force \
	--verbose \
	--option runtime \
	--entitlements $entitlementsPath \
	--timestamp Applications/$appName.app

if [ $? -ne 0 ] ; then  
	echo "Error: codesign error."
	exit
fi

pkgutil --check-signature "Applications/$appName.app"

pkgbuild --analyze \
	--root Applications \
	packages.plist

#debug
#less packages.plist

pkgbuild "tmp-$appName.pkg" --root Applications --component-plist packages.plist --identifier $identifier --version 1.0.0 --install-location "/Applications"

if [ $? -ne 0 ] ; then  
	echo "Error: pkgbuild error."
	exit
fi

productbuild --synthesize --package "tmp-$appName.pkg" Distribution.xml

if [ $? -ne 0 ] ; then  
	echo "Error: productbuild --synthesize error."
	exit
fi

#insert title
sed -e "s/\<pkg-ref/\<title\>$installerTitle\<\/title\>\n    \<allowed-os-versions\>\n        \<os-version min=\"10.15\"\/\>\n    \<\/allowed-os-versions\>\n    \<pkg-ref/" Distribution.xml >> tmp

#debug
#less tmp
#less Distribution.xml

mv tmp Distribution.xml

productbuild --distribution Distribution.xml \
	--package-path "tmp-$appName.pkg" \
	"tmp-$appName-Distribution.pkg"

if [ $? -ne 0 ] ; then  
	echo "Error: productbuild --distribution error."
	exit
fi

signedPackage="$appName.pkg"
productsign --sign "$developerIDInstaller" \
	"tmp-$appName-Distribution.pkg" \
	"$signedPackage"

if [ $? -ne 0 ] ; then  
	echo "Error: productsign error."
	exit
fi

rm tmp*.pkg

pkgutil --check-signature "$signedPackage"

xcrun altool --notarize-app \
	--file "$signedPackage" \
	--primary-bundle-id  $identifier \
	--username $appleId \
	--password $appPass
	
if [ $? -ne 0 ] ; then  
	echo "Error: xcrun error."
	exit
fi