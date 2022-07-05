#!/bin/sh

set -x 

export LOCATION=$1
export DOMAINNAME=$2
export SUDOUSER=$3
export WORKERNODECOUNT=$4
export CPDNAMESPACE=$5
export STORAGEOPTION=$6
export APIKEY=$7
export OPENSHIFTUSER=$8
export OPENSHIFTPASSWORD=$9
export CUSTOMDOMAIN=${10}
export CLUSTERNAME=${11}
export CHANNEL=${12}
export VERSION=${13}
export CPDCLI=11.0.0    # Version 11
export CPDCLIEDITION=SE # Standard Edition

export OPERATORNAMESPACE=ibm-common-services
export INSTALLERHOME=/home/$SUDOUSER/.ibm
export OCPTEMPLATES=/home/$SUDOUSER/.openshift/templates
export CPDTEMPLATES=/home/$SUDOUSER/.cpd/templates

runuser -l $SUDOUSER -c "mkdir -p $INSTALLERHOME"
runuser -l $SUDOUSER -c "mkdir -p $OCPTEMPLATES"
runuser -l $SUDOUSER -c "mkdir -p $CPDTEMPLATES"

# Service Account Token for CPD installation
runuser -l $SUDOUSER -c "oc new-project $CPDNAMESPACE"

# Service Account Token for CPD installation - This may not be required after all
runuser -l $SUDOUSER -c "oc new-project $OPERATORNAMESPACE"

## Installing cpd-cli - Right now, the links and name of files are hardcoded. Would be good to use the variables CPDCLI/CPDCLIEDITION to construct those
runuser -l $SUDOUSER -c "wget -O cpd-cli.tar.gz 'https://github.com/IBM/cpd-cli/releases/download/v11.0.0/cpd-cli-linux-SE-11.0.0.tgz'"
runuser -l $SUDOUSER -c "tar xvzf cpd-cli.tar.gz"
runuser -l $SUDOUSER -c "rm -f cpd-cli.tar.gz"
runuser -l $SUDOUSER -c "sudo cp -r cpd-cli-linux-SE-11.0.0-20/. /usr/bin/"
runuser -l $SUDOUSER -c "sudo chmod +x /usr/bin/cpd-cli"
# runuser -l $SUDOUSER -c "export PATH=$PWD/cpd-cli-linux-SE-11.0.0-20/:$PATH"

## Installing Podman or Docker - cpd-cli requires this a container engine as ansible playbooks are executed from a custom image
runuser -l $SUDOUSER -c "sudo yum -y install podman"

## Installing jq
runuser -l $SUDOUSER -c "wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O  $CPDTEMPLATES/jq"
runuser -l $SUDOUSER -c "sudo mv $CPDTEMPLATES/jq /usr/bin"
runuser -l $SUDOUSER -c "sudo chmod +x /usr/bin/jq"

# Setup the storage class value

if [[ $STORAGEOPTION == "nfs" ]];then 
    export STORAGECLASS_VALUE="nfs"
    export STORAGECLASS_RWO_VALUE="nfs"
elif [[ $STORAGEOPTION == "ocs" ]];then 
    export STORAGECLASS_VALUE="ocs-storagecluster-cephfs"
    export STORAGECLASS_RWO_VALUE="ocs-storagecluster-ceph-rbd"
fi

# Set url
if [[ $CUSTOMDOMAIN == "true" || $CUSTOMDOMAIN == "True" ]];then
export SUBURL="${CLUSTERNAME}.${DOMAINNAME}"
else
export SUBURL="${DOMAINNAME}.${LOCATION}.aroapp.io"
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

## Update Pull Secret
sudo cpd-cli manage add-icr-cred-to-global-pull-secret $APIKEY

## OLM Creation - TODO: Put some conditionals on whether or not Scheduler is required based on Watson Machine Learning Accelerator
sudo cpd-cli manage apply-olm \
--release=${VERSION} \
--components=cpfs,cpd_platform

sudo oc patch NamespaceScope common-service \
-n ${OPERATORNAMESPACE} \
--type=merge \
--patch='{"spec": {"csvInjector": {"enable": true} } }'

## Storage Configuration - this is dependant upon the storage mechanism chosen
sudo cpd-cli manage apply-cr \
--components=cpfs,cpd_platform \
--release=${VERSION} \
--cpd_instance_ns=${CPDNAMESPACE} \
--block_storage_class=${STORAGECLASS_VALUE} \
--file_storage_class=${STORAGECLASS_VALUE} \
--license_acceptance=true

echo "$(date) - ############### Script Complete #############"
