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


# Setup the storage class value

if [[ $STORAGEOPTION == "nfs" ]];then 
    export STORAGECLASS_VALUE="nfs"
elif [[ $STORAGEOPTION == "ocs" ]];then 
    export STORAGECLASS_VALUE="ocs-storagecluster-cephfs"
fi

## Login - via OC
var=1
while [ $var -ne 0 ]; do
echo "Attempting to login $OPENSHIFTUSER to https://api.${SUBURL}:6443"
oc login "https://api.${SUBURL}:6443" -u $OPENSHIFTUSER -p $OPENSHIFTPASSWORD --insecure-skip-tls-verify=true
var=$?
echo "exit code: $var"
done

## Login - via cpd-cli
# Logging on via oc binary is not enough. This login below writes the kubeconfig to the pod's filesystem which is used by the ansible playbooks
# TODO: Confirm if the cpd-cli login below implicitly performs an oc login
sudo cpd-cli manage login-to-ocp \
--server="https://api.${SUBURL}:6443" \
--username=${OPENSHIFTUSER} \
--password=${OPENSHIFTPASSWORD} \
--insecure-skip-tls-verify=true 


## Configure subscription and olm for PA
sudo cpd-cli manage apply-olm \
--release=${VERSION} \
--cpd_operator_ns=${CPDNAMESPACE} \
--components=planning_analytics

## Deploy PAService from exposed Operand - Note this deploys an instance of PAService but not the instance. So the Instance YAML must be created as per below.
sudo cpd-cli manage apply-cr \
--components=planning_analytics \
--release=${VERSION} \
--cpd_instance_ns=${CPDNAMESPACE} \
--license_acceptance=true

# TODO: Uncomment and test the below at a later date


# runuser -l $SUDOUSER -c "cat > $CPDTEMPLATES/ibm-pa-instance.yaml <<EOF
# apiVersion: pa.cpd.ibm.com/v1
# kind: PAServiceInstance
# metadata:
#   annotations:
#     ansible.sdk.operatorframework.io/verbosity: "3"
#   name: planning-analytics-instance
#   namespace: $CPDNAMESPACE
# spec:
#   common:
#     webapps_enabled: false
#   description: Planning Analytics Instance
#   metadata:
#     addon_version: $VERSION
#   paw_instance_name: planning-analytics-instance
#   persistence:
#     class: $STORAGECLASS_VALUE
#     size: 50Gi
#   scaleConfig: small
#   serviceInstanceName: planning-analytics-instance
#   tm1:
#     applications_location: <no value>
#     location: http://pa-service-provider-api:1212
#     name: tm1-instance
#     ssl_certs_for_tm1: <no value>
#     storage_class: $STORAGECLASS_VALUE
#     storage_size: 30Gi
#   tm1_internal_type: true
#   version: $VERSION
#   zenControlPlaneNamespace: $CPDNAMESPACE
#   zenServiceInstanceDisplayName: planning-analytics-instance
#   zenServiceInstanceNamespace: $CPDNAMESPACE
#   EOF"


## Creating pa-instance cr
# runuser -l $SUDOUSER -c "oc project $CPDNAMESPACE; oc create -f $CPDTEMPLATES/ibm-pa-instance.yaml"

# Check CR Status - PAServiceInstance

# SERVICE="PAServiceInstance"
# CRNAME="planning-analytics-instance"
# SERVICE_STATUS="paInstanceStatus"
  
# STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 

# while  [[ ! $STATUS =~ ^(Completed|Complete)$ ]]; do
#     echo "$CRNAME is Installing!!!!"
#     sleep 60 
#     STATUS=$(oc get $SERVICE $CRNAME -n $CPDNAMESPACE -o json | jq .status.$SERVICE_STATUS | xargs) 
#     if [ "$STATUS" == "Failed" ]
#     then
#         echo "**********************************"
#         echo "$CRNAME Installation Failed!!!!"
#         echo "**********************************"
#         exit 1
#     fi
# done 




# echo "*************************************"
# echo "$CRNAME Installation Finished!!!!"
# echo "*************************************"

echo "$(date) - ############### Script Complete #############"