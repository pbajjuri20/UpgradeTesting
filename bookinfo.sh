set -e

printHelp() {
  echo -e << EOF "Bookinfo example app installation script for Kiali QE
Description: This script
 * installs bookinfo example application for istio/maistra and starts traffic generator.
Usage:
 By exporting a variable BOOKINFO_NAMESPACE you specify where the bookinfo will be installed
 By exporting a variable CONTROL_PLANE_NAMESPACE you specify where is the istio/maistra running.
 By exporting a variable FEDERATION_ENABLED=true you enable just basic scenario which should work with federation
 By exporting a variable IS_MAISTRA=true you specify that maistra version of bookinfo should be used (false by default).
 By exporting a variable ISTIO_BRANCH you specify which istio repository branch will be used.
 By exporting a variable MAISTRA_BRANCH you specify which Maistra repository branch will be used.
 By exporting a variable MYSQL_ENABLED=true the ratings service version with mysql will be started.
 By exporting a variable MONGO_ENABLED=true the ratings service version with mongo db will be started.
 By exporting a variable TRAFFIC_GENERATOR=false the traffic generator will NOT be started (started by default).
 By exporting a variable IS_DISCONNECTED=true images from given registry on BASTION_HOST will be used. Images should be mirrored to the bastion host via https://gitlab.cee.redhat.com/istio/kiali-qe/kiali-qe-utils/blob/master/openshift/cluster-installation/psi/src/resources/ocp4/mirror-bookinfo.sh
 By exporting a variable OCP_ARCH=<architecture_type> bookinfo images will be pulled for the corresponding cluster architecture
 By exporting a variable BASTION_HOST=<bastion_host> you specify a bastion host with registry containing images.
"
EOF
  exit 0

}
if [ "$1" == "--help" ]; then
  printHelp
fi

BOOKINFO_NAMESPACE=${BOOKINFO_NAMESPACE:-""}
CONTROL_PLANE_NAMESPACE=${CONTROL_PLANE_NAMESPACE:-""}
ISTIO_BRANCH=${ISTIO_BRANCH:-"master"}
FEDERATION_ENABLED=${FEDERATION_ENABLED:-"false"}
IS_MAISTRA=${IS_MAISTRA:-"true"}
MAISTRA_BRANCH=${MAISTRA_BRANCH:-"maistra-2.0"}
MYSQL_ENABLED=${MYSQL_ENABLED:-"true"}
MONGO_ENABLED=${MONGO_ENABLED:-"true"}
TRAFFIC_GENERATOR=${TRAFFIC_GENERATOR:-"true"}
OCP_ARCH=${OCP_ARCH:-"x86_64"}

if [ "${IS_DISCONNECTED}" = "true" ]
then
  if [ -z ${BASTION_HOST} ]
  then
    echo "BASTION_HOST is required."
    exit 1
  fi
fi

oc new-project ${BOOKINFO_NAMESPACE} || true
oc project ${BOOKINFO_NAMESPACE}

oc project ${BOOKINFO_NAMESPACE}

# create a route for bookinfo using istio-ingressgateway service (traffic will go through the default istio ingress)
cat <<EOF | oc -n ${CONTROL_PLANE_NAMESPACE} apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${BOOKINFO_NAMESPACE}
spec:
  path: /
  to:
    kind: Service
    name: istio-ingressgateway
    weight: 100
  port:
    targetPort: http2
EOF

# needed for OCP 4.12+
cat <<SCC | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ${BOOKINFO_NAMESPACE}-scc
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
users:
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:bookinfo-details"
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:bookinfo-productpage"
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:bookinfo-ratings"
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:bookinfo-ratings=v2"
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:bookinfo-reviews"
- "system:serviceaccount:${BOOKINFO_NAMESPACE}:default"
SCC

# get host from the route
HOST=$(oc get route ${BOOKINFO_NAMESPACE} -n ${CONTROL_PLANE_NAMESPACE} -o=jsonpath='{.spec.host}')

# istio/maistra requires different configuration
if [ "$IS_MAISTRA" = "true" ]
then
  GITHUB_PREFIX="https://raw.githubusercontent.com/Maistra/istio/${MAISTRA_BRANCH}"
  # create new default servicemeshmemberroll if it does not exist
  if oc get servicemeshmemberroll default -n ${CONTROL_PLANE_NAMESPACE}
  then
    oc patch servicemeshmemberroll default -n ${CONTROL_PLANE_NAMESPACE} --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/members/0\", \"value\":\"${BOOKINFO_NAMESPACE}\"}]"
  else
  cat <<EOF | oc -n ${CONTROL_PLANE_NAMESPACE} apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: ${CONTROL_PLANE_NAMESPACE}
spec:
  members:
    - ${BOOKINFO_NAMESPACE}
EOF
  fi
else
  GITHUB_PREFIX="https://raw.githubusercontent.com/istio/istio/${ISTIO_BRANCH}"

  # istio specific config which is not needed for maistra
  oc adm policy add-scc-to-group privileged system:serviceaccounts:${BOOKINFO_NAMESPACE}
  oc adm policy add-scc-to-group anyuid system:serviceaccounts:${BOOKINFO_NAMESPACE}

  # requirement added probably in istio 1.5?
  cat <<EOF | oc -n ${BOOKINFO_NAMESPACE} apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

  oc label namespace ${BOOKINFO_NAMESPACE} istio-injection=enabled --overwrite
  # add new bookinfo namespace to accessible_namespaces
  KIALI_CR_NAMESPACE=$(oc get kiali --all-namespaces -o custom-columns=NAMESPACES_FOUND:.metadata.namespace | grep -v NAMESPACES_FOUND)
  oc patch kiali kiali -n ${KIALI_CR_NAMESPACE} --type='json' -p="[{\"op\": \"add\", \"path\": \"/spec/deployment/accessible_namespaces/0\", \"value\":\"${BOOKINFO_NAMESPACE}\"}]"

fi

# wget all yaml files before applying to cluster
wget -O bookinfo.yaml ${GITHUB_PREFIX}/samples/bookinfo/platform/kube/bookinfo.yaml
wget -O bookinfo-gateway.yaml ${GITHUB_PREFIX}/samples/bookinfo/networking/bookinfo-gateway.yaml
wget -O destination-rule-all.yaml ${GITHUB_PREFIX}/samples/bookinfo/networking/destination-rule-all.yaml
wget -O bookinfo-db.yaml ${GITHUB_PREFIX}/samples/bookinfo/platform/kube/bookinfo-db.yaml
wget -O bookinfo-ratings-v2.yaml ${GITHUB_PREFIX}/samples/bookinfo/platform/kube/bookinfo-ratings-v2.yaml
wget -O bookinfo-mysql.yaml ${GITHUB_PREFIX}/samples/bookinfo/platform/kube/bookinfo-mysql.yaml
wget -O bookinfo-ratings-v2-mysql.yaml ${GITHUB_PREFIX}/samples/bookinfo/platform/kube/bookinfo-ratings-v2-mysql.yaml
wget -O traffic-generator.yaml https://raw.githubusercontent.com/kiali/kiali-test-mesh/master/traffic-generator/openshift/traffic-generator.yaml

# Change image sources if multiarch
if [[ $OCP_ARCH == 'ppc64le' ]]; then
  if [ "${MAISTRA_BRANCH}" = "maistra-2.1" ]
	then
	  sed -i "s;:2.1.0;:2.1.0-ibm-p;g" bookinfo.yaml
      sed -i "s;:2.1.0;:2.1.0-ibm-p;g" bookinfo-db.yaml
      sed -i "s;:2.1.0;:2.1.0-ibm-p-1;g" bookinfo-ratings-v2.yaml
      sed -i "s;:2.1.0;:2.1.0-ibm-p;g" bookinfo-mysql.yaml
      sed -i "s;args:;#args: ;g" bookinfo-mysql.yaml
      sed -i "s;:2.1.0;:2.1.0-ibm-p;g" bookinfo-ratings-v2-mysql.yaml
  else 
	  #bookinfo.yaml
	  sed -i "s;image: ;image: quay.io/;g" bookinfo.yaml
	  sed -i "s;examples-bookinfo-reviews-v2:1.1.1;examples-bookinfo-reviews-v2:1.15.0-ibm-p-1;g" bookinfo.yaml
	  sed -i "s;examples-bookinfo-reviews-v3:1.1.1;examples-bookinfo-reviews-v3:1.15.0-ibm-p-1;g" bookinfo.yaml
	  sed -i "s;:1.1.1;:1.15.0-ibm-p;g" bookinfo.yaml
	  sed -i "s;:1.1.2;:1.15.0-ibm-p;g" bookinfo.yaml
	  sed -i "s;:2.0.0;:2.0.0-ibm-p;g" bookinfo.yaml
	  #bookinfo-gateway.yaml (no images)
	  #destination-rule-all.yaml (no images)
	  #bookinfo-db.yaml 
	  sed -i "s;image: ;image: quay.io/;g" bookinfo-db.yaml
	  sed -i "s;:1.1.1;:1.15.0-ibm-p;g" bookinfo-db.yaml
	  sed -i "s;:1.1.2;:1.15.0-ibm-p;g" bookinfo-db.yaml
	  sed -i "s;:2.0.0;:2.0.0-ibm-p;g" bookinfo-db.yaml
	  #bookinfo-ratings-v2.yaml 
	  sed -i "s;image: ;image: quay.io/;g" bookinfo-ratings-v2.yaml
	  sed -i "s;:1.1.1;:1.15.0-ibm-p;g" bookinfo-ratings-v2.yaml
	  sed -i "s;:1.1.2;:1.15.0-ibm-p;g" bookinfo-ratings-v2.yaml
	  sed -i "s;:2.0.0;:2.0.0-ibm-p-mod;g" bookinfo-ratings-v2.yaml
	  #bookinfo-mysql.yaml 
	  sed -i "s;image: ;image: quay.io/;g" bookinfo-mysql.yaml
	  sed -i "s;:1.1.1;:1.15.0-ibm-p;g" bookinfo-mysql.yaml
	  sed -i "s;:1.1.2;:1.15.0-ibm-p;g" bookinfo-mysql.yaml
	  sed -i "s;:2.0.0;:2.0.0-ibm-p;g" bookinfo-mysql.yaml
	  sed -i "s;args:;#args: ;g" bookinfo-mysql.yaml
	  #bookinfo-ratings-v2-mysql.yaml
	  sed -i "s;image: ;image: quay.io/;g" bookinfo-ratings-v2-mysql.yaml
	  sed -i "s;:1.1.1;:1.15.0-ibm-p;g" bookinfo-ratings-v2-mysql.yaml
	  sed -i "s;:1.1.2;:1.15.0-ibm-p;g" bookinfo-ratings-v2-mysql.yaml
	  sed -i "s;:2.0.0;:2.0.0-ibm-p;g" bookinfo-ratings-v2-mysql.yaml
  fi
  #traffic-generator.yaml
  sed -i 's;image: quay.io/kiali/kiali-test-mesh-traffic-generator:latest;image: quay.io/maistra/kiali-test-mesh-traffic-generator:0.0-ibm-p;g' traffic-generator.yaml

elif [[ $OCP_ARCH == 's390x' ]]; then
  #bookinfo.yaml
  sed -i "s;image: ;image: quay.io/;g" bookinfo.yaml
  sed -i "s;:1.1.1;:1.15.0-ibm-z;g" bookinfo.yaml
  sed -i "s;:1.1.2;:1.15.0-ibm-z;g" bookinfo.yaml
  sed -i "s;:2.0.0;:2.0.0-ibm-z;g" bookinfo.yaml
  #bookinfo-gateway.yaml (no images)
  #destination-rule-all.yaml (no images)
  #bookinfo-db.yaml 
  sed -i "s;image: ;image: quay.io/;g" bookinfo-db.yaml
  sed -i "s;:1.1.1;:1.15.0-ibm-z;g" bookinfo-db.yaml
  sed -i "s;:1.1.2;:1.15.0-ibm-z;g" bookinfo-db.yaml
  sed -i "s;:2.0.0;:2.0.0-ibm-z;g" bookinfo-db.yaml
  #bookinfo-ratings-v2.yaml 
  sed -i "s;image: ;image: quay.io/;g" bookinfo-ratings-v2.yaml
  sed -i "s;:1.1.1;:1.15.0-ibm-z;g" bookinfo-ratings-v2.yaml
  sed -i "s;:1.1.2;:1.15.0-ibm-z;g" bookinfo-ratings-v2.yaml
  sed -i "s;:2.0.0;:2.0.0-ibm-z;g" bookinfo-ratings-v2.yaml
  #bookinfo-mysql.yaml 
  sed -i "s;image: ;image: quay.io/;g" bookinfo-mysql.yaml
  sed -i "s;:1.1.1;:1.15.0-ibm-z;g" bookinfo-mysql.yaml
  sed -i "s;:1.1.2;:1.15.0-ibm-z;g" bookinfo-mysql.yaml
  sed -i "s;:2.0.0;:2.0.0-ibm-z;g" bookinfo-mysql.yaml
  #bookinfo-ratings-v2-mysql.yaml
  sed -i "s;image: ;image: quay.io/;g" bookinfo-ratings-v2-mysql.yaml
  sed -i "s;:1.1.1;:1.15.0-ibm-z;g" bookinfo-ratings-v2-mysql.yaml
  sed -i "s;:1.1.2;:1.15.0-ibm-z;g" bookinfo-ratings-v2-mysql.yaml
  sed -i "s;:2.0.0;:2.0.0-ibm-z;g" bookinfo-ratings-v2-mysql.yaml
  #traffic-generator.yaml
  sed -i 's;image: quay.io/kiali/kiali-test-mesh-traffic-generator:latest;image: quay.io/maistra/kiali-test-mesh-traffic-generator:0.0-ibm-z;g' traffic-generator.yaml
fi




# deploy bookinfo
if [ "${IS_DISCONNECTED}" = "true" ]
then
  sed -i "s;quay.io/maistra/examples;${BASTION_HOST}:55555/maistra/examples;g" bookinfo.yaml
fi
oc apply -f bookinfo.yaml
# filter traffic coming from istio ingress, we want traffic relevant only for this bookinfo instance (in case we have multiple bookinfo instances)
if [ "${FEDERATION_ENABLED}" = "true" ]
then
  # TODO: having specific host in gateway hosts is not working?? why?
  # this will only update virtual service not gataway
  sed -i "s/^  - \"\*\"/  - ${HOST}/g" bookinfo-gateway.yaml
else
  sed -i "s/\*/${HOST}/g" bookinfo-gateway.yaml
fi
oc apply -f bookinfo-gateway.yaml

if [ "${FEDERATION_ENABLED}" != "true" ]
then
  # create default destination rules
  # edit destination rules so it contains only valid rules (to have everything green in Kiali UI)
  sed -i '/v2-mysql-vm/,+2d'  destination-rule-all.yaml
  oc apply -f destination-rule-all.yaml
  # remove not existing subset (to have everything green in Kiali UI)
  oc patch DestinationRule details -n ${BOOKINFO_NAMESPACE} -p '{"spec":{"subsets":[{"labels": {"version": "v1"},"name": "v1"}]}}' --type=merge
fi

if [ "${MONGO_ENABLED}" = "true" ]
then
  if [ "${IS_DISCONNECTED}" = "true" ]
  then
    sed -i "s;quay.io/maistra/examples;${BASTION_HOST}:55555/maistra/examples;g" bookinfo-db.yaml bookinfo-ratings-v2.yaml
  fi
  oc apply -f bookinfo-db.yaml
  oc apply -f bookinfo-ratings-v2.yaml
fi
if [ "${MYSQL_ENABLED}" = "true" ]
then
  if [ "${IS_DISCONNECTED}" = "true" ]
  then
    sed -i "s;quay.io/maistra/examples;${BASTION_HOST}:55555/maistra/examples;g" bookinfo-mysql.yaml bookinfo-ratings-v2-mysql.yaml
  fi
  oc apply -f bookinfo-mysql.yaml
  oc apply -f bookinfo-ratings-v2-mysql.yaml
fi

if [ "${TRAFFIC_GENERATOR}" = "true" ]
then
  # start traffic generator in bookinfo namespace
  curl https://raw.githubusercontent.com/kiali/kiali-test-mesh/master/traffic-generator/openshift/traffic-generator-configmap.yaml | SILENT='true' \
  DURATION='0s' ROUTE="http://${HOST}/productpage" RATE="1"  envsubst | oc apply -n ${BOOKINFO_NAMESPACE} -f -
  if [ "${IS_DISCONNECTED}" = "true" ]
  then
    sed -i "s;quay.io/kiali/kiali-test-mesh-traffic-generator;${BASTION_HOST}:55555/kiali/kiali-test-mesh-traffic-generator;g" traffic-generator.yaml
  fi
  oc apply --validate=false -n ${BOOKINFO_NAMESPACE} -f traffic-generator.yaml
fi
