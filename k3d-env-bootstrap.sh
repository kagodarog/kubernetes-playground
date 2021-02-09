#!/bin/sh
set -x

#setup your k3d clustername 
clustername=bigCastlext

if [ "${pwd}" != "~/k3dtest" ]; then
    cd ~/k3dtest
fi    

dashboard_secret_name='my-dashboard-sa'
reg_name='registry'
reg_port='5000'
k8s_version='1.18.8'

#Check if docker is running.
rep=$(curl -s --unix-socket /var/run/docker.sock http://ping > /dev/null)
status=$?
if [ "${status}" = "7" ]; then
	sudo service docker start
	echo $?
	sleep 10
fi	

#:Start a local Docker registry (unless it already exists)
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "${reg_port}:5000" --name "${reg_name}" -v registry-images:/var/lib/registry  \
    registry:2 
fi

#configs for kind cluster

# Create a kind cluster
# - Configures containerd to use the local Docker registry
# - Enables Ingress on ports 80 and 443
# cat <<EOF | kind create cluster --image kindest/node:v${k8s_version} --config=-
# kind: Cluster
# apiVersion: kind.x-k8s.io/v1alpha4
# containerdConfigPatches:
# - |-
#   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
#     endpoint = ["http://${reg_name}:${reg_port}"]
# nodes:
# - role: control-plane
#   kubeadmConfigPatches:
#   - |
#     kind: InitConfiguration
#     nodeRegistration:
#       kubeletExtraArgs:
#         node-labels: "ingress-ready=true"
#   extraPortMappings:
#   - containerPort: 80
#     hostPort: 80
#     protocol: TCP
#   - containerPort: 443
#     hostPort: 443
#     protocol: TCP
# EOF

# Delete previous cluster
clusterexist=$(k3d cluster list | awk '{print $1}' | grep $clustername)
if [ ${clusterexist} = ${clustername} ]; then
      echo -n "Cluster ${clustername} exists, do you want to delete it (y/n? "
      read answer
      if [ "$answer" != "y" ]; then
          echo "script will exit!"
          exit 0
      else 
          echo "...................cluster is deleting....."
          k3d cluster delete --all
      fi         
fi       

# Create K3d cluster

k3d  cluster create ${clustername} --servers 1 --agents 2 --image rancher/k3s:latest --port 8081:80@loadbalancer --port 8443:443@loadbalancer  --k3s-server-arg '--no-deploy=traefik' \
--volume "${PWD}/registries.yaml:/etc/rancher/k3s/registries.yaml" --volume "$(pwd)/helm-ingress-nginx.yaml:/var/lib/rancher/k3s/server/manifests/helm-ingress-traefik.yaml" --volume "/home/ubuntu/k3dtest/word-press-mysql-playground/mysql-data:/etc/pv-data/mysql" \
--volume "/home/ubuntu/k3dtest/word-press-mysql-playground/wordpress-data:/etc/pv-data/wordpress" --volume "/home/ubuntu/k3dtest/awamoapps/data-volumes:/etc/pe-db-data/mysql" --volume "/home/ubuntu/k3dtest/awamoapps/data-volumes/mysqldb-init:/etc/pe-db-data/mysql/init"

export KUBECONFIG=$(k3d kubeconfig write bigCastlext)

#Connect the local Docker registry with the k3d network
docker network connect "${clustername}" "${reg_name}" > /dev/null 2>&1 &

# Deploy the nginx Ingress controller
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml

#deploy kubernetes-dashboard dashboard
kubectl apply -f kubernetes-dashboard-insecure-configs.yaml

#kubernetes dashboard deployment with ingress and listening on https://tegasdashboard.com  update your local host file with the domain pointing to localhost or 127.0.0.1
kubectl apply -f ingress-dashboard2.yaml

# Create the service account in the current namespace 
# (we assume default)
kubectl create serviceaccount ${dashboard_secret_name}  -n kubernetes-dashboard
# Give that service account root on the cluster
kubectl create clusterrolebinding ${dashboard_secret_name} \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:${dashboard_secret_name}
# Find the secret that was created to hold the token for the SA
sleep 10
secretname=$(kubectl get secrets -n kubernetes-dashboard -o json | jq --raw-output '.items[-1].metadata.name')
# Show the contents of the secret to extract the token

#setup ECR authentication.
kubectl create secret  -n default generic ecr-renew-cred-demo \
  --from-literal=REGION=eu-central-1 \
  --from-literal=ID=${kube_ecr_accesskey} \
  --from-literal=SECRET=${kube_ecr_secret}

kubectl apply -f ecr-login/

#run job to authenticate to ECR
kubectl create -f ecr-token-gen.yaml


#nginx deployment,service and ingress and listening on https://cockpit.tegasdashboard.com  update your local host file with the domain pointing to localhost or 127.0.0.1
kubectl apply -f nginx-app.yaml

#add prometheous operator helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update

#install chart
helm install prometheus prometheus-community/kube-prometheus-stack
kubectl apply -f serviceMonitor.yaml

sleep 10
kubectl describe secret $secretname -n kubernetes-dashboard
# Expose ingress controller service
traefik_pod=$(kubectl get pods --field-selector=status.phase=Running -n kube-system | grep  -v svclb | grep ingress-controller-nginx)
while [ $? != "0" ]; do
      sleep 15
      traefik_svc=$(kubectl get svc -n kube-system | grep nginx)
done     

sudo -E kubectl -n kube-system --address 0.0.0.0 port-forward svc/ingress-controller-nginx-ingress-controller-nginx 443 &>/dev/null &

while [ $? != "0" ]; do
      sleep 15 
      sudo -E kubectl -n kube-system --address 0.0.0.0 port-forward svc/ingress-controller-nginx-ingress-nginx-controller 443 &>/dev/null &
done       

if [ $? != "0" ]; then
    echo "Failure to port-forward"
    exit 1
else
    echo "success"
fi
