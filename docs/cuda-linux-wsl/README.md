# CUDA Linux/WSL/Hyper-V Installation Instructions

## Enable GPU partitioning in Hyper-V

Follow this guide, but with some changes: https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a
Update the kernel compilation script with the matching WSL branch: https://github.com/microsoft/WSL2-Linux-Kernel/branches/all (e.g. `linux-msft-wsl-6.1.y` for Debian Bookworm)


`ln -s /usr/lib/wsl/lib/nvidia-smi /usr/local/bin/`


https://learn.microsoft.com/en-us/azure-stack/hci/manage/attach-gpu-to-linux-vm
https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a
https://forum.level1techs.com/t/gpu-paravirtualization-hyper-v-with-linux-guest/198336
https://github.com/seflerZ/oneclick-gpu-pv/blob/main/ubuntu-gpu-pv.ps1
https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmgpupartitionadapter?view=windowsserver2022-ps
https://www.youtube.com/watch?v=aZtuiLYnb_g&t=38s
https://www.tenforums.com/virtualization/195745-tutorial-passing-through-gpu-hyper-v-guest-vm.html
https://learn.microsoft.com/en-us/powershell/module/hyper-v/get-vmhostpartitionablegpu?view=windowsserver2022-ps
https://jmmv.dev/2022/02/wsl-ssh-access.html

Convert VMDK to VHDX: https://gist.github.com/rahilwazir/69a750b70348459875cbf40935af02cb
Docs: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/partition-assign-vm-gpu?tabs=powershell&pivots=windows-server

Example below. Replace gnarly GPU name with output from `Get-VMPartitionableGpu`. Note: On Windows 11, the cmdlet is named `Get-VMHostPartitionableGpu`
```
Import-Module -Force Hyper-V
Get-VMPartitionableGpu | FL Name,ValidPartitionCounts
Set-VMPartitionableGpu -Name "\\?\PCI#VEN_10DE&DEV_2484&SUBSYS_404C1458&REV_A1#4&3834d97&0&0008#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV" -PartitionCount 32
```

Assign GPU to VM
```
Get-VMGpuPartitionAdapter -VMName $VMName
Add-VMGpuPartitionAdapter -VMName $VMName
Get-VMGpuPartitionAdapter -VMName $VMName | FL InstancePath,PartitionId,PartitionVfLuid
```

## WSL

Links:
- CUDA on WSL User Guide: https://docs.nvidia.com/cuda/wsl-user-guide/index.html
- Installing the NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- WSL CUDA toolkit download: https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=WSL-Ubuntu&target_version=2.0&target_type=deb_local

### Debian WSL

apt update
apt install wget curl git net-tools debian-goodies
apt upgrade
wget https://developer.download.nvidia.com/compute/cuda/12.4.1/local_installers/cuda-repo-debian12-12-4-local_12.4.1-550.54.15-1_amd64.deb
sudo dpkg -i cuda-repo-debian12-12-4-local_12.4.1-550.54.15-1_amd64.deb
sudo cp /var/cuda-repo-debian12-12-4-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo add-apt-repository contrib
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-4

#### Container runtime

Is this necessary?

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg   && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker

## Linux

Links:
- NVIDIA CUDA Installation Guide for Linux: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/
- Support for Container Device Interface: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html

## Test
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html

## Ollama

`docker run -d --gpus=all -v /mnt/g/llm-models:/root/.ollama -p 11434:11434 --name ollama ollama/ollama`