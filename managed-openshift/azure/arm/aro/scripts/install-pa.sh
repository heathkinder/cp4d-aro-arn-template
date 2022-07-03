#!/bin/sh
export LOCATION=$1
export DOMAINNAME=$2
export SUDOUSER=$3
export WORKERNODECOUNT=$4
export CPDNAMESPACE=$5
export STORAGEOPTION=$6
export APIKEY=$7
export OPENSHIFTUSER=$8
export OPENSHIFTPASSWORD=$9
export CUSTOMDOMAIN=$10
export CLUSTERNAME=${11}
export CHANNEL=${12}
export VERSION=${13}

export OPERATORNAMESPACE=openshift-operators
export INSTALLERHOME=/home/$SUDOUSER/.ibm
export OCPTEMPLATES=/home/$SUDOUSER/.openshift/templates
export CPDTEMPLATES=/home/$SUDOUSER/.cpd/templates

# Set url
if [[ $CUSTOMDOMAIN == "true" || $CUSTOMDOMAIN == "True" ]];then
export SUBURL="${CLUSTERNAME}.${DOMAINNAME}"
else
export SUBURL="${DOMAINNAME}.${LOCATION}.aroapp.io"
fi

#Login
var=1
while [ $var -ne 0 ]; do
echo "Attempting to login $OPENSHIFTUSER to https://api.${SUBURL}:6443"
oc login "https://api.${SUBURL}:6443" -u $OPENSHIFTUSER -p $OPENSHIFTPASSWORD --insecure-skip-tls-verify=true
var=$?
echo "exit code: $var"
done

# Setup the storage class value

if [[ $STORAGEOPTION == "nfs" ]];then 
    export STORAGECLASS_VALUE="nfs"
elif [[ $STORAGEOPTION == "ocs" ]];then 
    export STORAGECLASS_VALUE="ocs-storagecluster-cephfs"
fi


# PA subscription and CR creation 

runuser -l $SUDOUSER -c "cat > $CPDTEMPLATES/ibm-pa-sub.yaml <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-planning-analytics-operator
  namespace: $OPERATORNAMESPACE
spec:
  channel: $CHANNEL
  installPlanApproval: Automatic
  name: ibm-planning-analytics-operator
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
  startingCSV: ibm-planning-analytics-operator.v4.0.9
EOF"

runuser -l $SUDOUSER -c "cat > $CPDTEMPLATES/ibm-pa-service.yaml <<EOF
apiVersion: pa.cpd.ibm.com/v1
kind: PAService
metadata:
  annotations:
    ansible.sdk.operatorframework.io/verbosity: "3"
  labels:
    app.kubernetes.io/instance: ibm-planning-analytics-service
    app.kubernetes.io/managed-by: ibm-planning-analytics-operator
    app.kubernetes.io/name: ibm-planning-analytics-service
  name: ibm-planning-analytics-service
  namespace: $CPDNAMESPACE
spec:
  license:
    accept: true
  version: \"$VERSION\"
EOF"

runuser -l $SUDOUSER -c "cat > $CPDTEMPLATES/ibm-pa-instance.yaml <<EOF
apiVersion: pa.cpd.ibm.com/v1
kind: PAServiceInstance
metadata:
  annotations:
    ansible.sdk.operatorframework.io/verbosity: "3"
  name: planning-analytics-instance
  namespace: $CPDNAMESPACE
spec:
  common:
    webapps_enabled: false
  description: Planning Analytics Instance
  metadata:
    addon_version: $VERSION
  paw_instance_name: planning-analytics-instance
  persistence:
    class: $STORAGECLASS_VALUE
    size: 50Gi
  scaleConfig: small
  serviceInstanceName: planning-analytics-instance
  tm1:
    applications_location: <no value>
    location: http://pa-service-provider-api:1212
    name: tm1-instance
    ssl_certs_for_tm1: <no value>
    storage_class: $STORAGECLASS_VALUE
    storage_size: 30Gi
  tm1_internal_type: true
  version: $VERSION
  zenControlPlaneNamespace: $CPDNAMESPACE
  zenServiceInstanceDisplayName: planning-analytics-instance
  zenServiceInstanceNamespace: $CPDNAMESPACE
  EOF"

## Creating Subscription 

runuser -l $SUDOUSER -c "oc create -f $CPDTEMPLATES/ibm-pa-sub.yaml"
runuser -l $SUDOUSER -c "echo 'Sleeping for 2m' "
runuser -l $SUDOUSER -c "sleep 2m"

# Wait for the operator to be up and running prior to deploying the CR's given by the subscription's CSV

podname="ibm-planning-analytics-operator"
name_space=$OPERATORNAMESPACE
status="unknown"
while [ "$status" != "Running" ]
do
  pod_name=$(oc get pods -n $name_space | grep $podname | awk '{print $1}' )
  ready_status=$(oc get pods -n $name_space $pod_name  --no-headers | awk '{print $2}')
  pod_status=$(oc get pods -n $name_space $pod_name --no-headers | awk '{print $3}')
  echo $pod_name State - $ready_status, podstatus - $pod_status
  if [ "$ready_status" == "1/1" ] && [ "$pod_status" == "Running" ]
  then 
  status="Running"
  else
  status="starting"
  sleep 10 
  fi
  echo "$pod_name is $status"
done

## Creating pa-service cr

runuser -l $SUDOUSER -c "oc project $CPDNAMESPACE; oc create -f $CPDTEMPLATES/ibm-pa-service.yaml"

# Check CR Status - PAService

SERVICE="PAService"
CRNAME="ibm-planning-analytics-service"
SERVICE_STATUS="paAddonStatus"
  
STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 

while  [[ ! $STATUS =~ ^(Completed|Complete)$ ]]; do
    echo "$CRNAME is Installing!!!!"
    sleep 60 
    STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 
    if [ "$STATUS" == "Failed" ]
    then
        echo "**********************************"
        echo "$CRNAME Installation Failed!!!!"
        echo "**********************************"
        exit 1
    fi
done 

## Creating pa-service cr

runuser -l $SUDOUSER -c "oc project $CPDNAMESPACE; oc create -f $CPDTEMPLATES/ibm-pa-instance.yaml"

# Check CR Status - PAServiceInstance

SERVICE="PAServiceInstance"
CRNAME="planning-analytics-instance"
SERVICE_STATUS="paInstanceStatus"
  
STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 

while  [[ ! $STATUS =~ ^(Completed|Complete)$ ]]; do
    echo "$CRNAME is Installing!!!!"
    sleep 60 
    STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 
    if [ "$STATUS" == "Failed" ]
    then
        echo "**********************************"
        echo "$CRNAME Installation Failed!!!!"
        echo "**********************************"
        exit 1
    fi
done 




echo "*************************************"
echo "$CRNAME Installation Finished!!!!"
echo "*************************************"

echo "$(date) - ############### Script Complete #############"