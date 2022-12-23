#!/bin/bash
#It will get the deployed cluster version
OCP_VERSION="$(oc version | grep "Server Version" | cut -d ":" -f2 | cut -d "." -f1,2 | tr -d " ")"
#create Jaeger operator from RH catalog
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
#create servicemesh operator from RH catalog
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

sleep 60

#create 2.3 smcp for OSSM

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
  version: v2.3
EOF

oc wait --for condition=Ready -n istio-system smcp/basic --timeout 120s

export BOOKINFO_NAMESPACE=bookinfo
echo $BOOKINFO_NAMESPACE

export CONTROL_PLANE_NAMESPACE=istio-system
echo $CONTROL_PLANE_NAMESPACE

sh ./bookinfo.sh

oc wait --for condition=Ready -n istio-system smmr/default --timeout 120s

oc new-project istio-system22 || true

sleep 60

#create 2.2 smcp for OSSM

cat <<EOF | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system22
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

oc wait --for condition=Ready -n istio-system22 smcp/basic --timeout 120s

export BOOKINFO_NAMESPACE=bookinfo22
echo $BOOKINFO_NAMESPACE

export CONTROL_PLANE_NAMESPACE=istio-system22
echo $CONTROL_PLANE_NAMESPACE

sh ./bookinfo.sh

oc wait --for condition=Ready -n istio-system22 smmr/default --timeout 120s

oc new-project istio-system21 || true

sleep 60

# create 2.1 smcp for OSSM

cat <<EOF | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system21
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
  version: v2.1
EOF


oc wait --for condition=Ready -n istio-system21 smcp/basic --timeout 120s

export BOOKINFO_NAMESPACE=bookinfo21
echo $BOOKINFO_NAMESPACE

export CONTROL_PLANE_NAMESPACE=istio-system21
echo $CONTROL_PLANE_NAMESPACE

sh ./bookinfo.sh

oc wait --for condition=Ready -n istio-system21 smmr/default --timeout 120s


#3. Create stage catalog in same name as RH catalog

cat <<EOF | oc apply -f -
# This will assure that images will be pulled either from registry.redhat.io or registry.stage.redhat.io
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: stage-registry
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.stage.redhat.io
    source: registry.redhat.io
EOF

#4. Create the Stage Image Content Source Policy

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: stage-manifests
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry.stage.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}
  updateStrategy:
    registryPoll:
      interval: "30m"
EOF

sh ./wait.sh
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

ISTIO_STATUS=$(oc get pods -n openshift-operators | grep istio-operator | awk '{print $3}')
if [ $ISTIO_STATUS = "Running" ]; then
   echo "Istio operator installed."
else
   echo "Waiting for Istio operator installation"
   sleep 20
fi

oc get pods -n openshift-operators | grep istio-operator
#4. Check operator upgrade progress

oc get csv -n openshift-operators

KIALI_UPGRADE_STATUS=$(oc get csv -n openshift-operators | grep kiali | awk '{print $6}')
if [ $KIALI_UPGRADE_STATUS = "Succeeded" ]; then
   echo "Kiali Operator upgraded successfully."
else
   echo "Kiali Operator upgraded is failed"
exit
fi

SM_UPGRADE_STATUS=$(oc get csv -n openshift-operators | grep servicemeshoperator | awk '{print $9}')
if [ $SM_UPGRADE_STATUS = "Succeeded" ]; then
   echo "ServiceMesh Operator upgraded successfully."
else
   echo "ServiceMesh Operator upgraded is failed"
exit
fi


oc wait --for condition=Ready -n istio-system smcp/basic --timeout 20s

oc wait --for condition=Ready -n istio-system22 smcp/basic --timeout 40s

oc wait --for condition=Ready -n istio-system21 smcp/basic --timeout 40s

oc get pods -n istio-system
oc get pods -n istio-system22
oc get pods -n istio-system21


VERIFY_PODS_STATUS_IS_23=$(oc get pods -n istio-system | grep kiali | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_IS_23 = "Running" ]; then
   echo "Verfied all the istio-system pods installed successfully"
else
   echo "2.3 Pods are not installed successfully"
exit
fi

VERIFY_PODS_STATUS_IS_22=$(oc get pods -n istio-system22 | grep kiali | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_IS_22 = "Running" ]; then
   echo "Verfied all the istio-system22 pods installed successfully"
else
   echo "2.2 Pods are not installed successfully"
exit
fi

VERIFY_PODS_STATUS_IS_21=$(oc get pods -n istio-system21 | grep kiali | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_IS_21 = "Running" ]; then
   echo "Verfied all the istio-system21 pods installed successfully"
else
   echo "2.1 Pods are not installed successfully"
exit
fi

oc get pods -n bookinfo
oc get pods -n bookinfo22
oc get pods -n bookinfo21

VERIFY_PODS_STATUS_BI_21=$(oc get pods -n bookinfo21 | grep 'kiali\|details|' | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_BI = "Running" ]; then
   echo "Verfied all the bookinfo21 pods"
else
   echo "bookinfo21 pods are not running successfully "
   sleep 20
exit
fi

VERIFY_PODS_STATUS_BI_22=$(oc get pods -n bookinfo22 | grep 'kiali\|productpage\|ratings\|reviews\|details|' | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_BI = "Running" ]; then
   echo "Verfied all the bookinfo22 pods"
else
   echo "bookinfo22 pods are not running successfully "
   sleep 20
exit
fi

VERIFY_PODS_STATUS_BI=$(oc get pods -n bookinfo | grep 'kiali\|productpage\|ratings\|reviews\|details|' | awk '{print $3}')
if [ $VERIFY_PODS_STATUS_BI = "Running" ]; then
   echo "Verfied all the bookinfo23 pods"
else
   echo "bookinfo23 pods are not running successfully "
   sleep 20
exit
fi

oc version
