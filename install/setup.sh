#!/bin/sh
set -e

# Base URL the mTLS failure redirect points to. Override when the diary listener isn't on port 80.
DIARY_URL="${DIARY_URL:-http://diary.example.com}"

pushd ..

# Certificates
if [ ! -f certs/ca.crt ]; then
  ./install/generate-certs.sh
fi

# Deploy the Gateways

# Gateway
kubectl create namespace ingress-gw --dry-run=client -o yaml | kubectl apply -f -

# Server cert for api.example.com, and the CA the Gateway trusts for client certs.
printf "\nDeploy server certificate and client CA ...\n"
kubectl -n ingress-gw create secret tls api-example-com-tls --cert=certs/server.crt --key=certs/server.key --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ingress-gw create configmap client-ca --from-file=ca.crt=certs/ca.crt --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f gateways/gw-parameters.yaml
kubectl apply -f gateways/gw.yaml

# Policies first, so the API route is never reachable without the client cert check.
printf "\nDeploy mTLS failure policies ...\n"
kubectl apply -f policies/require-valid-client-cert-trafficpolicy.yaml
sed "s#\${DIARY_URL}#${DIARY_URL}#g" policies/mtls-failure-redirect-listenerpolicy.yaml | kubectl apply -f -

# Create namespaces if they do not yet exist
kubectl create namespace httpbin --dry-run=client -o yaml | kubectl apply -f -

# Label the default namespace, so the gateway will accept the HTTPRoute from that namespace.
printf "\nLabel default namespace ...\n"
kubectl label namespaces default --overwrite shared-gateway-access="true"

# Deploy the HTTPBin application
printf "\nDeploy HTTPBin application ...\n"
kubectl apply -f apis/httpbin.yaml

# Reference Grants
printf "\nDeploy Reference Grants ...\n"
kubectl apply -f referencegrants/httpbin-ns/default-ns-httproute-service-rg.yaml

# HTTPRoute
printf "\nDeploy HTTPRoute ...\n"
kubectl apply -f routes/api-example-com-httproute.yaml

# Envoy's diary: the page clients without a valid cert get redirected to.
printf "\nDeploy the diary page ...\n"
kubectl create namespace diary --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespaces diary --overwrite shared-gateway-access="true"
kubectl -n diary create configmap diary-html --from-file=index.html=apis/diary/index.html --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f apis/diary.yaml
kubectl apply -f routes/diary-example-com-httproute.yaml

popd
