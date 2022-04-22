#!/bin/bash

get_abs_filename() {
  # $1 : relative filename
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

## These need to be absolute paths.  License should be in 
LICENSE_FILE=$(get_abs_filename "./config/2021-sonatype-license.lic")
DATA_DIR=$(get_abs_filename "./sonatype-work/nexus3")

ETC_DIR=$DATA_DIR'/etc/'
INSTALL_DIR=nx-server
OPTIONS_FILE=./${INSTALL_DIR}/bin/nexus.vmoptions
PROPERTIES_FILE=${ETC_DIR}nexus.properties
NEXUS=./${INSTALL_DIR}/bin/nexus

## not a public endpoint but works well for finding the latest version of nxrm
PRODUCT_INFO="https://cx-cms.cx.sonatype.com/products?Name=Nexus%20Repository%203"
VERSION_NUM=$(curl -s ${PRODUCT_INFO} | jq -r '.[0].version')
DOWNLOAD="https://download.sonatype.com/nexus/3/"
FILE="nexus-${VERSION_NUM}-01-mac.tgz"


$NEXUS stop

## stop should work but this will also kill any leftover processes from the server not shutting down gracefully.
lsof -t -i tcp:8081 | xargs kill -9

## remove comment to clear out all of the old nxrm data.
rm -r ${INSTALL_DIR} ## ${DATA_DIR}

## download the binary
wget ${DOWNLOAD}${FILE}

## uncompressing to a temp folder.
mkdir ${INSTALL_DIR} temp
tar -xvf ${FILE} -C ./temp

## moving runtime to the INSTALL_DIR and dumping temp folder.
mv -v ./temp/nexus*/{.,}* ./${INSTALL_DIR}/
rm -r ${FILE} temp

## remap data directory in nexus.vmoptions
sed -i '.bak' 's@../sonatype-work/nexus3@'$DATA_DIR'@g' $OPTIONS_FILE
echo '-Djava.util.prefs.userRoot='$DATA_DIR'/javaprefs' >> $OPTIONS_FILE

## check to see if data dir already exists.  If so we will nto update the nexus.properties file.
if [ ! -d $ETC_DIR ] 
then
	mkdir -p $ETC_DIR

	## these are to remove the license stored on macs. Assuming we are loading them with this property
	defaults delete com.sonatype.nexus
	defaults read ~/Library/Preferences/com.sonatype.nexus.plist

	## this forces the use of H2 on start-up. 
	echo 'nexus.datastore.enabled=true' >> $PROPERTIES_FILE
	## bypass requirement for new admin password.  admin:admin123
	echo 'nexus.security.randompassword=false' >> $PROPERTIES_FILE
	## load the license file from local link.  Startup will fail if not found or valid.
	echo 'nexus.licenseFile='$LICENSE_FILE >> $PROPERTIES_FILE
fi

## fire it up, fingers crossed!!
$NEXUS start

## wait for the status 200 before making additional configuration calls through the API.
until $(curl --output /dev/null --silent --head --fail http://localhost:8081/service/rest/v1/status); do
    printf '.'
    sleep 5
done

echo "Ready!"

## setting the anon access on startup so it doesn't ask me to do it.
curl -X 'PUT' -i -u admin:admin123 -H 'accept: application/json' -H 'Content-Type: application/json' \
	-d '{"enabled": true,"userId": "anonymous","realmName": "NexusAuthorizingRealm"}' \
	'http://localhost:8081/service/rest/v1/security/anonymous'


