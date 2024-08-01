#!/bin/bash
# Sync ZTA score from CrowdStrike to Jamf
# please see https://blog.ssh.nu/post/jamf-zta for more info
# this is dirty

CROWDSTRIKE_APIBASE="https://api.REGION.crowdstrike.com"
ZTA_EXTENSION_ATTRIBUTE_ID=""
GROUP_ID=""
CROWDSTRIKE_APICLIENT_ID=""
CROWDSTRIKE_APISECRET=""
JAMF_BASE_URL="https://REPLACEME.jamfcloud.com"
JAMF_USER=""
JAMF_PW=""

getCSToken() {
CROWDSTRIKE_TOKEN=$(curl -s -X POST "$CROWDSTRIKE_APIBASE/oauth2/token" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "client_id=$CROWDSTRIKE_APICLIENT_ID" \
 -d "client_secret=$CROWDSTRIKE_APISECRET" \
 -d "grant_type=client_credentials" | jq -r .access_token)
}

getJamfToken() {
JAMFAUTHTOKEN=$( /usr/bin/curl \
--request POST \
--silent \
--url "$JAMF_BASE_URL/api/v1/auth/token" \
--user "$JAMF_USER:$JAMF_PW" )
JAMF_TOKEN=$(echo "$JAMFAUTHTOKEN" | jq -r '.token' )
}

getJamfDevices() {
JAMF_GROUP=$(curl --silent --request GET --url $JAMF_BASE_URL/JSSResource/computergroups/id/$SCOPED_HOSTS_GROUP --header 'accept: application/json' --header "Authorization: Bearer $JAMF_TOKEN")
echo "[+] Scope: $(echo $JAMF_GROUP|jq -r '.computer_group.computers | length') devices!"
LIST_OF_DEVICES=$(echo $JAMF_GROUP | jq -r '.computer_group.computers[].serial_number')
}

getCSDeviceId() {
LIST_DEVICE_URL="$CROWDSTRIKE_APIBASE/devices/queries/devices/v1"
CS_DEVICE_RESPONSE=$(curl -s -X GET -H "Authorization: Bearer $CROWDSTRIKE_TOKEN" "$LIST_DEVICE_URL?filter=serial_number:'$HOSTNAME'")
CS_DEVICE_ID=$(echo "$CS_DEVICE_RESPONSE" | jq -r '.resources[0]')

if [ -n "$CS_DEVICE_ID" ]; then
 echo "[+] CrowdStrike DeviceID: $CS_DEVICE_ID"
else
  echo "[ERR] Device not found or ID not available."
  echo ""
  echo $CS_RESPONSE
fi
}

getZTAScore() {
ZTA_URL="$CROWDSTRIKE_APIBASE/zero-trust-assessment/entities/assessments/v1"
CS_ZTA_RESPONSE=$(curl -s -X GET -H "Authorization: Bearer $CROWDSTRIKE_TOKEN" "$ZTA_URL?ids=$CS_DEVICE_ID")
ZTA_SCORE=$(echo $CS_ZTA_RESPONSE | jq -r '.resources[].assessment.overall')
echo "[+] ZTA Score: $ZTA_SCORE"
}

getJamfDeviceID() {
JAMF_DEVICE_RESPONSE=$(curl -fsSL --request GET --url $JAMF_BASE_URL/JSSResource/computers/serialnumber/$HOSTNAME --header 'accept: application/json' --header "Authorization: Bearer $JAMF_TOKEN")
JAMF_DEVICE_ID=$(echo $JAMF_DEVICE_RESPONSE | jq -r '.computer.general.id')
echo "[+] Jamf DeviceID: $JAMF_DEVICE_ID"
}

putZTAScore() {
echo "[+] Writing ZTA Score..."
ZTAXML="<computer><extension_attributes><extension_attribute><id>$ZTA_EXTENSION_ATTRIBUTE_ID</id><value>$ZTA_SCORE</value></extension_attribute></extension_attributes></computer>"
JAMF_ZTA_RESPONSE=$(curl --write-out "%{http_code}" --silent --output /dev/null --request PUT --url "$JAMF_BASE_URL/JSSResource/computers/id/$JAMF_DEVICE_ID" --header "Authorization: Bearer $JAMF_TOKEN" --header "Content-Type: text/xml" --data "$ZTAXML")

if [ "$JAMF_ZTA_RESPONSE" -eq 201 ]; then
  echo "[+] OK, $HOSTNAME updated with ZTA Score $ZTA_SCORE!"
else
  echo "[ERR] $HOSTNAME FAILED!"
  echo ""
  echo $JAMF_ZTA_RESPONSE
fi
}

getJamfToken
getJamfDevices
getCSToken
for HOSTNAME in $LIST_OF_DEVICES; do
  getCSDeviceId
  getZTAScore
  getJamfDeviceID
  putZTAScore
done
