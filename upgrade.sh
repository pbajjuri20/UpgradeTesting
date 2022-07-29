#!/bin/bash
set -e​
#Update this param value based on the OCP version on which the script is executed.
OCP_VERSION="4.10"
#create Jaeger operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jaeger-product
  namespace: openshift-operators
spec:
  channel: stable
  name: jaeger-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
sleep 20
JAEGER_STATUS=$(oc get pods -n openshift-operators | grep jaeger | awk '{print $3}')
if [ $JAEGER_STATUS = "Running" ]; then
   echo "Jaeger operator installed."
else
   echo "Waiting for Jaeger operator installation"
   sleep 20
fi
oc get pods -n openshift-operators | grep jaeger
#Create kiali operator from RH catalog 
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
sleep 20
KIALI_STATUS=$(oc get pods -n openshift-operators | grep kiali | awk '{print $3}')
if [ $KIALI_STATUS = "Running" ]; then
   echo "Kiali operator installed."
else
   echo "Waiting for Kiali operator installation"
   sleep 20
fi
oc get pods -n openshift-operators | grep kiali
#create servicemesh operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
sleep 20
ISTIO_STATUS=$(oc get pods -n openshift-operators | grep istio-operator | awk '{print $3}')
if [ $ISTIO_STATUS = "Running" ]; then
   echo "Istio operator installed."
else
   echo "Waiting for Istio operator installation"
   sleep 20
fi
oc get csv -n openshift-operators
oc get pods -n openshift-operators | grep istio
oc new-project istio-system || true
#create smcp for OSSM
cat <<EOF | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  tracing:
    type: Jaeger
    sampling: 10000
  policy:
    type: Istiod
  addons:
    grafana:
      enabled: true
    jaeger:
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
    prometheus:
      enabled: true
  telemetry:
    type: Istiod
  version: v2.2
EOF
sleep 120
oc get smcp -n istio-system
sleep 60
#3. Create stage catalog in same name as RH catalog
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: stage-manifests
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: "registry.stage.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}"
  updateStrategy:
    registryPoll:
      interval: "30m"
EOF
sleep 120
#4 Create kiali operator from Stage catalog 
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  name: kiali-ossm
  source: stage-manifests
  sourceNamespace: openshift-marketplace
EOF
sleep 20
KIALI_STATUS=$(oc get pods -n openshift-operators | grep kiali | awk '{print $3}')
if [ $KIALI_STATUS = "Running" ]; then
   echo "Kiali operator installed."
else
   echo "Waiting for Kiali operator installation"
   sleep 20
fi
oc get pods -n openshift-operators | grep kiali
#create servicemesh operator from Stage Catalog
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  name: servicemeshoperator
  source: stage-manifests
  sourceNamespace: openshift-marketplace
EOF
#4. Check operator upgrade progress
sleep 25
oc get csv -n openshift-operators
oc get smcp -n istio-system
