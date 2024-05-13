# CUDA Linux/WSL Installation Instructions


## WSL

Links:
- CUDA on WSL User Guide: https://docs.nvidia.com/cuda/wsl-user-guide/index.html
- Installing the NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- WSL CUDA toolkit download: https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=WSL-Ubuntu&target_version=2.0&target_type=deb_local

### Debian WSL

apt update
apt install wget curl
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