#!/bin/sh
KUBE_TOKEN=`cat /var/run/secrets/kubernetes.io/serviceaccount/token`
NAMESPACE=`cat /var/run/secrets/kubernetes.io/serviceaccount/namespace`

if [ -z ${KUBERNETES_DEPLOY_NAME} ]; then
  export KUBERNETES_DEPLOY_NAME="consul"
fi

if [ -z ${CONSUL_SERVER_COUNT} ]; then
  export CONSUL_SERVER_COUNT=3
fi

if [ -z ${CONSUL_HTTP_PORT} ]; then
  export CONSUL_HTTP_PORT=8500
fi

if [ -z ${CONSUL_HTTPS_PORT} ]; then
  export CONSUL_HTTPS_PORT=8243
fi

if [ -z ${CONSUL_DNS_PORT} ]; then
  export CONSUL_DNS_PORT=53
fi

if [ -z ${CONSUL_SERVICE_HOST} ]; then
  export CONSUL_SERVICE_HOST="127.0.0.1"
fi

if [ -z ${CONSUL_WEB_UI_ENABLE} ]; then
  export CONSUL_WEB_UI_ENABLE="true"
fi

if [ -z ${CONSUL_SSL_ENABLE} ]; then
  export CONSUL_SSL_ENABLE="true"
fi

if [ ${CONSUL_SSL_ENABLE} == "true" ]; then
  if [ ! -z ${CONSUL_SSL_KEY} ] &&  [ ! -z ${CONSUL_SSL_CRT} ]; then
    echo ${CONSUL_SSL_KEY} > /etc/consul/ssl/consul.key
    echo ${CONSUL_SSL_CRT} > /etc/consul/ssl/consul.crt
  else
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/consul/ssl/consul.key -out /etc/consul/ssl/consul.crt -days 365 -subj "/CN=consul.kube-system.svc.cluster.local"
  fi
fi

export CONSUL_IP=`hostname -i`

if [ -z ${ENVIRONMENT} ] || [ -z ${MASTER_TOKEN} ] || [ -z ${GOSSIP_KEY} ]; then
  echo "Error: ENVIRONMENT, MASTER_TOKEN and GOSSIP_KEY environment vars must be set"
  exit 1
fi

LIST_IPS=`curl -sSk https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/pods -H "Authorization: Bearer $KUBE_TOKEN" | jq ".items[] | select(.status.containerStatuses[].name==\"$KUBERNETES_DEPLOY_NAME\") | .status .podIP"`

echo "done1"
echo $LIST_IPS
echo "done11"

#basic test to see if we have ${CONSUL_SERVER_COUNT} number of containers alive
VALUE='0'

while [ $VALUE != ${CONSUL_SERVER_COUNT} ]; do
  echo "waiting 10s on all the consul containers to spin up"
  sleep 10
  LIST_IPS=`curl -sSk https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/kube-system/pods -H "Authorization: Bearer $KUBE_TOKEN" | jq ".items[] | select(.status.containerStatuses[].name==\"$KUBERNETES_DEPLOY_NAME\") | .status .podIP"`

  echo "done2"
  echo $LIST_IPS
  echo "done22"

  echo "$LIST_IPS" | sed -e 's/$/,/' -e '$s/,//' > tester
  VALUE=`cat tester | wc -l`
done

LIST_IPS_FORMATTED=`echo "$LIST_IPS" | sed -e 's/$/,/' -e '$s/,//'`

TEMP_LIST_IPS_FORMATTED=`echo $LIST_IPS_FORMATTED | tr -d "\n" | sed -e 's/"/@/g'`

sed -i "s,%%ENVIRONMENT%%,$ENVIRONMENT,"             /etc/consul/config.json
sed -i "s,%%MASTER_TOKEN%%,$MASTER_TOKEN,"           /etc/consul/config.json
sed -i "s,%%GOSSIP_KEY%%,$GOSSIP_KEY,"               /etc/consul/config.json
sed -i "s,%%CONSUL_HTTP_PORT%%,$CONSUL_HTTP_PORT,"   /etc/consul/config.json
sed -i "s,%%CONSUL_HTTPS_PORT%%,$CONSUL_HTTPS_PORT," /etc/consul/config.json
sed -i "s,%%CONSUL_DNS_PORT%%,$CONSUL_DNS_PORT,"     /etc/consul/config.json
#sed -i 's|%%LIST_PODIPS%%|"$LIST_IPS_FORMATTED"|'      /etc/consul/config.json

cat /etc/consul/config.json \
   | sed -e "s/%%LIST_PODIPS%%/$TEMP_LIST_IPS_FORMATTED/" -e 's/@/"/g' > /etc/consul/temp.json
mv /etc/consul/temp.json /etc/consul/config.json

cmd="consul agent -server -config-dir=/etc/consul -dc ${ENVIRONMENT} -bootstrap-expect ${CONSUL_SERVER_COUNT}"

if [ ! -z ${CONSUL_DEBUG} ]; then
  ls -lR /etc/consul
  cat /etc/consul/config.json
  echo "${cmd}"
  sed -i "s,INFO,DEBUG," /etc/consul/config.json
fi

consul agent -server -config-dir=/etc/consul -dc ${ENVIRONMENT} -bootstrap-expect ${CONSUL_SERVER_COUNT}
