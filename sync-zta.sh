#!/bin/bash
# Sync ZTA score from CrowdStrike to Jamf
# please see https://blog.ssh.nu/post/jamf-zta for more info
# this is dirty

CROWDSTRIKE_APIBASE="https://api.REGION.crowdstrike.com"
SCOPED_HOSTS_GROUP=""
JAMF_APIBASE="https://REPLACEME.jamfcloud.com"
JAMF_USER=""
JAMF_PW=""
ZTA_OS_ATTRIBUTE_ID=""
ZTA_SENSOR_ATTRIBUTE_ID=""
ZTA_OVERALL_ATTRIBUTE_ID=""
LOGFILE=""

echo "$(date) - Hi!" >> $LOGFILE

getCSToken() {
  CROWDSTRIKE_TOKEN=$(curl -s -X POST "$CROWDSTRIKE_APIBASE/oauth2/token" -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$CROWDSTRIKE_APICLIENT_ID" -d "client_secret=$CROWDSTRIKE_APISECRET" -d "grant_type=client_credentials" | jq -r .access_token)
}

getJamfToken() {
  JAMFAUTHTOKEN=$(curl -s -X POST "$JAMF_APIBASE/api/v1/auth/token" -u "$JAMF_USER:$JAMF_PW")
  JAMF_TOKEN=$(echo "$JAMFAUTHTOKEN" | jq -r '.token' )
}

getJamfDevices() {
  JAMF_GROUP=$(curl -s $JAMF_APIBASE/JSSResource/computergroups/id/$SCOPED_HOSTS_GROUP -H 'accept: application/json' -H "Authorization: Bearer $JAMF_TOKEN")
  echo "[+] Scope: $(echo $JAMF_GROUP|jq -r '.computer_group.computers | length') devices!"
  echo "Scope: $(echo $JAMF_GROUP|jq -r '.computer_group.computers | length') devices!" >> $LOGFILE
  LIST_OF_DEVICES=$(echo $JAMF_GROUP | jq -r '.computer_group.computers[].serial_number')
}

getCSDeviceId() {
  LIST_DEVICE_URL="$CROWDSTRIKE_APIBASE/devices/queries/devices/v1"
  CS_DEVICE_RESPONSE=$(curl -s -H "Authorization: Bearer $CROWDSTRIKE_TOKEN" "$LIST_DEVICE_URL?filter=serial_number:'$SERIAL_NUM'")
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
  CS_ZTA_RESPONSE=$(curl -s -H "Authorization: Bearer $CROWDSTRIKE_TOKEN" "$CROWDSTRIKE_APIBASE/zero-trust-assessment/entities/assessments/v1?ids=$CS_DEVICE_ID")
  echo $CS_ZTA_RESPONSE >> $CS_DEVICE_ID.txt
  ZTA_OVERALL_SCORE=$(echo $CS_ZTA_RESPONSE | jq -r '.resources[].assessment.overall')
  ZTA_OS_SCORE=$(echo $CS_ZTA_RESPONSE | jq -r '.resources[].assessment.os')
  ZTA_SENSOR_SCORE=$(echo $CS_ZTA_RESPONSE | jq -r '.resources[].assessment.sensor_config')
  ZTA_SCORE=$(echo "a: $ZTA_OVERALL_SCORE, o: $ZTA_OS_SCORE, s: $ZTA_SENSOR_SCORE")
  echo "[+] $ZTA_SCORE"
}

getJamfDeviceID() {
  JAMF_DEVICE_RESPONSE=$(curl -fsSL $JAMF_APIBASE/JSSResource/computers/serialnumber/$SERIAL_NUM -H 'accept: application/json' -H "Authorization: Bearer $JAMF_TOKEN")
  JAMF_DEVICE_ID=$(echo $JAMF_DEVICE_RESPONSE | jq -r '.computer.general.id')
  echo "[+] Jamf DeviceID: $JAMF_DEVICE_ID"
}

putZTAScore() {
  echo "[+] Writing ZTA Score..."
  ZTAXML="<computer><extension_attributes><extension_attribute><id>$ZTA_OS_ATTRIBUTE_ID</id><value>$ZTA_OS_SCORE</value></extension_attribute><extension_attribute><id>$ZTA_SENSOR_ATTRIBUTE_ID</id><value>$ZTA_SENSOR_SCORE</value></extension_attribute><extension_attribute><id>$ZTA_OVERALL_ATTRIBUTE_ID</id><value>$ZTA_OVERALL_SCORE</value></extension_attribute></extension_attributes></computer>"
  JAMF_ZTA_RESPONSE=$(curl --write-out "%{http_code}" -s --output /dev/null -X PUT "$JAMF_APIBASE/JSSResource/computers/id/$JAMF_DEVICE_ID" -H "Authorization: Bearer $JAMF_TOKEN" -H "Content-Type: text/xml" -d "$ZTAXML")
  if [ "$JAMF_ZTA_RESPONSE" -eq 201 ]; then
    echo "[+] OK, $SERIAL_NUM updated with $ZTA_SCORE!"
    echo "$SERIAL_NUM,$ZTA_SCORE">>$LOGFILE
  else
    echo "[ERR] $SERIAL_NUM FAILED!"
    echo "[ERR] $SERIAL_NUM" >> $LOGFILE
    echo ""
    echo $JAMF_ZTA_RESPONSE
  fi
}

getJamfToken
getJamfDevices
getCSToken
for SERIAL_NUM in $LIST_OF_DEVICES; do
  getCSDeviceId
  getZTAScore
  getJamfDeviceID
  putZTAScore
done

echo "$(date) - Bye!" >> $LOGFILE
echo "--------" >> $LOGFILE
