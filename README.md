# kubernetes-playground
repository contains test kubernetes yaml configs.
This has been tested on WSL2 Ubuntu 20 on Windows 10.

You need to have installed k3d using instructions on link https://k3d.io/#installation.
In k3d-env-bootstrap.sh script, At the K3d create cluster command,mount your volumes on your local machines where to store mysql databases for persistence.This is an optional step.
The above script:
  - Installs a kubernetes dashboard
  - Setup an Nginx Ingress Controller using Helm by mounting the helm file as a volume in K3d.
  - Sets the cluster for a local docker registry
  - Runs a cronjob that authenticated to AWS ECR and you need to have available AWS accesskey and AWS secretkey credentials beforehand as environment variables
    (optional if you don't use ECR private repos for your images)
  - Install a prometheus operator that comes loaded with grafana and installation is by Helm.
  
  You may then run port forward command below to access you ingress via port 443 on your local machine.
    
    *sudo -E kubectl -n kube-system --address 0.0.0.0 port-forward svc/ingress-controller-nginx-ingress-nginx-controller 443 &>/dev/null &*
    
    **svc/ingress-controller-nginx-ingress-nginx-controller** could be different depending on your ingress service name
