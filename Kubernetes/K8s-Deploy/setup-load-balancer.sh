# Passo 7: Instalar o Kube-VIP como um Cloud Provider
kubectl apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml

# Passo 8: Instalar MetalLB
# Criar o namespace para MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml

# Instalar MetalLB (versão nativa se estiver usando Kubernetes 1.24 ou superior)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Baixar e configurar o pool de endereços IP de MetalLB usando o range especificado anteriormente
lbrange="192.168.18.8-192.168.18.28"  # ajuste conforme necessário
curl -sO https://raw.githubusercontent.com/brunocza/proxmox-scripts/main/Kubernetes/K8s-Deploy/ipAddressPool
sed 's/$lbrange/'$lbrange'/g' ipAddressPool > $HOME/ipAddressPool.yaml

# Aplicar o arquivo de configuração do pool de endereços IP
kubectl apply -f $HOME/ipAddressPool.yaml

# Passo 9: Testar com Nginx
# Este passo irá implantar uma instância de Nginx e expô-la usando MetalLB como um LoadBalancer
kubectl apply -f https://raw.githubusercontent.com/inlets/inlets-operator/master/contrib/nginx-sample-deployment.yaml -n default
kubectl expose deployment nginx-1 --port=80 --type=LoadBalancer -n default

echo -e " \033[32;5mWaiting for K3S to sync and LoadBalancer to come online\033[0m"

# Aguardar até que o pod Nginx esteja pronto
while [[ $(kubectl get pods -l app=nginx -n default -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
   sleep 1
done


# Step 10: Deploy IP Pools and l2Advertisement
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=component=controller \
                --timeout=120s

                
# kubectl apply -f ipAddressPool.yaml
kubectl apply -f $HOME/ipAddressPool.yaml
kubectl apply -f https://github.com/brunocza/proxmox-scripts/blob/main/Kubernetes/K8s-Deploy/l2Advertisement.yaml


# Exibir informações úteis sobre o cluster
kubectl get nodes
kubectl get svc
kubectl get pods --all-namespaces -o wide

echo -e " \033[32;5mHappy Kubing! Access Nginx at EXTERNAL-IP above\033[0m"
