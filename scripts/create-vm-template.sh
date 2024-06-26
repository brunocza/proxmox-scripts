#!/bin/bash
ubuntuImageURL=https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img
ubuntuImageFilename=$(basename $ubuntuImageURL)
ubuntuImageBaseURL=$(dirname $ubuntuImageURL)
proxmoxTemplateID="${TMPL_ID:-9000}"
proxmoxTemplateName="${TMPL_NAME:-ubuntu-2204}"
scriptTmpPath=/tmp/proxmox-scripts
imageSavePath=/opt/proxmox-images  # Caminho específico para salvar a imagem

init () {
    if [ $(id -u) != 0 ]; then
        echo "Este script deve ser executado como root." >&2
        exit 1
    fi

    apt-get update && apt-get install sudo -y
    clean
    installRequirements
    mkdir -p $scriptTmpPath
    mkdir -p $imageSavePath  # Cria o diretório específico para a imagem
    vmDiskStorage="${PM_STORAGE:-$(sudo pvesm status | awk '$2 != "dir" {print $1}' | tail -n 1)}"
    cd $scriptTmpPath
}

installRequirements () {
    sudo dpkg -l libguestfs-tools &> /dev/null || \
    sudo apt update -y && sudo apt install libguestfs-tools -y
}

getImage () {
    local _img=$imageSavePath/$ubuntuImageFilename
    local imgSHA256SUM=$(curl -s $ubuntuImageBaseURL/SHA256SUMS | grep $ubuntuImageFilename | awk '{print $1}')
    
    if [ -f "$_img" ]; then
        echo "Verificando integridade da imagem existente..."
        if [[ $(sha256sum $_img | awk '{print $1}') == $imgSHA256SUM ]]; then
            echo "A imagem já existe e a assinatura está OK."
        else
            echo "A imagem existente está corrompida. Baixando novamente..."
            wget $ubuntuImageURL -O $_img
        fi
    else
        echo "Baixando a imagem do Ubuntu..."
        wget $ubuntuImageURL -O $_img
    fi

    sudo cp $_img $scriptTmpPath/$ubuntuImageFilename
}

enableCPUHotplug () {
    echo "Habilitando hotplug de CPU..."
    sudo virt-customize -a $scriptTmpPath/$ubuntuImageFilename \
    --run-command 'echo "SUBSYSTEM==\"cpu\", ACTION==\"add\", TEST==\"online\", ATTR{online}==\"0\", ATTR{online}=\"1\"" > /lib/udev/rules.d/80-hotplug-cpu.rules' 
}

installQemuGA () {
    echo "Instalando QEMU Guest Agent..."
    sudo virt-customize -a $scriptTmpPath/$ubuntuImageFilename \
    --run-command 'apt update -y && apt install qemu-guest-agent -y && systemctl enable qemu-guest-agent && systemctl start qemu-guest-agent'
}

resetMachineID () {
    echo "Resetando o ID da máquina..."
    sudo virt-customize -x -a $scriptTmpPath/$ubuntuImageFilename \
    --run-command '> /etc/machine-id && systemd-machine-id-setup'
}

setRandomSeed () {
    echo "Definindo a semente aleatória..."
    sudo virt-customize -a $scriptTmpPath/$ubuntuImageFilename \
    --run-command 'mkdir -p /var/lib/systemd && dd if=/dev/urandom of=/var/lib/systemd/random-seed bs=512 count=1 && chmod 600 /var/lib/systemd/random-seed'
}

createProxmoxVMTemplate () {
    echo "Criando template de VM no Proxmox..."
    sudo qm destroy $proxmoxTemplateID --purge || true
    sudo qm create $proxmoxTemplateID --name $proxmoxTemplateName --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
    sudo qm set $proxmoxTemplateID --scsihw virtio-scsi-single 
    sudo qm set $proxmoxTemplateID --virtio0 $vmDiskStorage:0,import-from=$scriptTmpPath/$ubuntuImageFilename
    sudo qm set $proxmoxTemplateID --boot c --bootdisk virtio0
    sudo qm set $proxmoxTemplateID --ide2 $vmDiskStorage:cloudinit
    sudo qm set $proxmoxTemplateID --serial0 socket --vga serial0
    sudo qm set $proxmoxTemplateID --agent enabled=1,fstrim_cloned_disks=1
    sudo qm template $proxmoxTemplateID
}

clean () { 
    rm -rf $scriptTmpPath 
}

init
getImage
enableCPUHotplug
installQemuGA
resetMachineID
setRandomSeed
createProxmoxVMTemplate
clean
