#!/bin/bash -eux

# The unprivileged user that will be running packer/using the boxes.
export HUMAN="`whoami`"

# Handle self referencing, sourcing etc.
if [[ $0 != $BASH_SOURCE ]]; then
  export CMD=$BASH_SOURCE
else
  export CMD=$0
fi

# Ensure a consistent working directory so relative paths work.
pushd `dirname $CMD` > /dev/null
BASE=`pwd -P`
popd > /dev/null
cd $BASE

function provide-limits() {

  # Find out how much RAM is installed, and what 50% would be in KB.
  TOTALMEM=`free -k | grep -E "^Mem:" | awk -F' ' '{print $2}'`
  HALFMEM=`echo $(($TOTALMEM/2))`

  # Increase the limits for our human user.
  printf "$HUMAN    soft    memlock    $HALFMEM\n" > /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    hard    memlock    $HALFMEM\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    soft    nproc      65536\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    hard    nproc      65536\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    soft    nofile     1048576\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    hard    nofile     1048576\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    soft    stack      unlimited\n" >> /etc/security/limits.d/50-$HUMAN.conf
  printf "$HUMAN    hard    stack      unlimited\n" >> /etc/security/limits.d/50-$HUMAN.conf

  chcon "system_u:object_r:etc_t:s0" /etc/security/limits.d/50-$HUMAN.conf

  # Now do the same for the root user.
  printf "root      soft    memlock    $HALFMEM\n" > /etc/security/limits.d/50-root.conf
  printf "root      hard    memlock    $HALFMEM\n" >> /etc/security/limits.d/50-root.conf
  printf "root      soft    nproc      65536\n" >> /etc/security/limits.d/50-root.conf
  printf "root      hard    nproc      65536\n" >> /etc/security/limits.d/50-root.conf
  printf "root      soft    nofile     1048576\n" >> /etc/security/limits.d/50-root.conf
  printf "root      hard    nofile     1048576\n" >> /etc/security/limits.d/50-root.conf
  printf "root      soft    stack      unlimited\n" >> /etc/security/limits.d/50-root.conf
  printf "root      hard    stack      unlimited\n" >> /etc/security/limits.d/50-root.conf

  chcon "system_u:object_r:etc_t:s0" /etc/security/limits.d/50-root.conf
}

function provide-libvirt() {
  # Repo setup.
  yum --assumeyes --enablerepo=extras install epel-release centos-release-qemu-ev

  # Libvirt Install
  yum --assumeyes --enablerepo=epel --enablerepo=centos-qemu-ev install \
    libvirt libvirt-client libvirt-daemon libvirt-daemon-config-network \
    libvirt-daemon-config-nwfilter libvirt-daemon-driver-interface \
    libvirt-daemon-driver-network libvirt-daemon-driver-nodedev \
    libvirt-daemon-driver-nwfilter libvirt-daemon-driver-qemu \
    libvirt-daemon-driver-secret libvirt-daemon-driver-storage \
    libvirt-daemon-kvm qemu qemu-common qemu-img qemu-kvm qemu-kvm-common \
    qemu-kvm-tools qemu-system-x86 qemu-user

  # Setup the Libvirt, QEMU and KVM Groups
  usermod -aG kvm root
  usermod -aG qemu root
  usermod -aG libvirt root
  usermod -aG kvm $HUMAN
  usermod -aG qemu $HUMAN
  usermod -aG libvirt $HUMAN

  # Disable Libvirt Automatic Startup
  systemctl disable libvirtd.service
  systemctl disable libvirt-guests.service
}

function provide-lxc() {
  # LXC install (Optional)
  yum --assumeyes --enablerepo=epel install lxc lua-lxc lxc-libs \
   libvirt-daemon-driver-lxc libvirt-daemon-lxc

  # Disable LXC Automatic Startup
  systemctl disable lxc.service
}

function provide-virtmanager() {
  # Remove Viewer / Virt Manager Client Install (Optional)
  yum --assumeyes install virt-manager virt-manager-common gvnc \
    gtk-vnc2 spice-glib spice-gtk3  libvirt-python \
    libvirt-glib libvirt-gconfig libvirt-gobject
}

function provide-vmware() {

  if [ ! -f $BASE/VMware-Workstation-Full-12.5.9-7535481.x86_64.bundle ]; then
      tput setaf 1; printf "\nError. The VMware install bundle is missing.\n\n"; tput sgr0
      exit 2
  fi

  # VMware Workstation Install
  chmod +x VMware-Workstation-Full-12.5.9-7535481.x86_64.bundle
  bash VMware-Workstation-Full-12.5.9-7535481.x86_64.bundle --console \
    --required --eulas-agreed --set-setting vmware-workstation serialNumber "${VMWARE_WORKSTATION}"

  # Disable VMWare Automatic Startup
  systemctl disable vmware.service
  systemctl disable vmware-USBArbitrator.service
  systemctl disable vmware-workstation-server.service

  # Setup the Virtual Interfaces as Trusted
  if [ -f /usr/bin/firewall-cmd ]; then
    firewall-cmd --permanent --zone=trusted --add-interface=vmnet1
    firewall-cmd --permanent --zone=trusted --add-interface=vmnet8
  fi
}

function provide-vbox() {
  # Virtual Box Repo
  cp virtualbox.repo /etc/yum.repos.d/virtualbox.repo
  chown root:root /etc/yum.repos.d/virtualbox.repo
  chcon system_u:object_r:system_conf_t:s0 /etc/yum.repos.d/virtualbox.repo

  cp virtualbox.pem /etc/pki/rpm-gpg/RPM-GPG-KEY-Oracle-Vbox
  chown root:root /etc/pki/rpm-gpg/RPM-GPG-KEY-Oracle-Vbox
  chcon system_u:object_r:cert_t:s0 /etc/pki/rpm-gpg/RPM-GPG-KEY-Oracle-Vbox

  # Virtual Box Install
  yum --assumeyes --enablerepo=virtualbox install VirtualBox-5.2.x86_64

  # Virtual Box Extensions, if X windows is installed.
  if [ -f /usr/bin/X ]; then

    # Determine the download URL.
    VBOXVER=`VBoxManage --version | awk -F'r' '{print $1}'`
    VBOXEXT="Oracle_VM_VirtualBox_Extension_Pack-${VBOXVER}.vbox-extpack"
    VBOXEXTURL="http://download.virtualbox.org/virtualbox/${VBOXVER}/${VBOXEXT}"

    # Download the extension pack.
    curl "${VBOXEXTURL}" > "${VBOXEXT}"

    # Calculate the license hash.
    VBOXACCEPT=`tar --extract --to-stdout --file="${VBOXEXT}" ./ExtPack-license.txt | sha256sum | awk -F' ' '{print $1}'`

    # Uncomment this line to install the VirtualBox extensions.
    VBoxManage extpack install --replace --accept-license="${VBOXACCEPT}" "${VBOXEXT}"

    # Cleanup the downloaded file.
    rm --force "${VBOXEXT}"
  fi

  # Disable Virtual Box Automatic Startup
  systemctl disable vboxautostart-service.service
  systemctl disable vboxballoonctrl-service.service
  systemctl disable vboxweb-service.service
  systemctl disable vboxdrv.service

  # Add the key users to the vboxusers group.
  usermod -aG vboxusers root
  usermod -aG vboxusers $HUMAN

  # Setup the Virtual Interfaces as Trusted
  if [ -f /usr/bin/firewall-cmd ]; then
    firewall-cmd --permanent --zone=trusted --add-interface=vibr0
  fi

  # Fix a permission issue to avoid spurious error messages in the system log.
  if [ -f /usr/lib/virtualbox/VMMR0.r0 ]; then
    chmod 755 /usr/lib/virtualbox/VMMR0.r0
  fi
  if [ -f /usr/lib/virtualbox/VBoxDDR0.r0 ]; then
    chmod 755 /usr/lib/virtualbox/VBoxDDR0.r0
  fi

  # If there is a set of user preferences, relocate the default box directory.
  if [ -f $HOME/.config/VirtualBox/VirtualBox.xml ]; then
     sed -i "s/defaultMachineFolder=\"[^\"]*\"/defaultMachineFolder=\"${HOME////\\/}\/\.virtualbox\"/g" /home/ladar/.config/VirtualBox/VirtualBox.xml
  fi

}

function provide-docker() {
  # Ensure the EPEL Repo is Available
  yum --assumeyes --enablerepo=extras install epel-release

  # Docker Install
  yum --assumeyes --enablerepo=extras --enablerepo=epel install docker \
    docker-common docker-selinux docker-logrotate docker-latest \
    docker-latest-logrotate docker-latest-v1.10-migrator \
    python-docker-py python-docker-scripts python-dockerfile-parse

  # Setup Docker Latest as the Default
  sed -i -e "s/#DOCKERBINARY=\/usr\/bin\/docker-latest/DOCKERBINARY=\/usr\/bin\/docker-latest/g" /etc/sysconfig/docker

  # Setup the Docker Group
  groupadd docker
  usermod -aG docker root
  usermod -aG docker $HUMAN

  # Disable Docker Automatic Startup
  systemctl disable docker-cleanup.service
  systemctl disable docker-latest-storage-setup.service
  systemctl disable docker-latest.service
  systemctl disable docker-storage-setup.service
  systemctl disable docker.service
  systemctl disable docker-cleanup.timer

  # Setup the Virtual Interfaces as Trusted
  if [ -f /usr/bin/firewall-cmd ]; then
    firewall-cmd --permanent --zone=trusted --add-interface=docker0
  fi
}

function provide-vagrant() {

  # Attempt to find out the latest Vagrant version automatically.
  export VAGRANT_VERSION=`curl --silent https://www.vagrantup.com/ | grep button | grep Download | sed -e "s/.*Download \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/g"`

  # Download Vagrant
  curl --location --output "$BASE/vagrant_${VAGRANT_VERSION}_x86_64.rpm" "https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_x86_64.rpm"

  # Install Vagrant
  yum --assumeyes install $BASE/vagrant_${VAGRANT_VERSION}_x86_64.rpm

  # The Libvirt Headers are Required for the Vagrant Plugin
  yum --assumeyes install libvirt-devel

  # Vagrant Libvirt Plugin
  vagrant plugin install vagrant-libvirt

  # Delete the Download
  rm --force $BASE/vagrant_${VAGRANT_VERSION}_x86_64.rpm
}

function provide-packer() {

  # Attempt to find out the latest Packer version automatically.
  export PACKER_VERSION=`curl --silent https://www.packer.io/ | grep button | grep Download | sed -e "s/.*Download \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/g"`

  # Download Packer
  curl --location --output "$BASE/packer_${PACKER_VERSION}_linux_amd64.zip" "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip"

  # Decompress
  unzip "$BASE/packer_${PACKER_VERSION}_linux_amd64.zip"

  # Install
  install "$BASE/packer" /usr/local/bin/
  chown root:root /usr/local/bin/packer
  chcon unconfined_u:object_r:bin_t:s0 /usr/local/bin/packer

  # Ensure bash/csh use the local bin version instead of the default.
  printf "alias packer='/usr/local/bin/packer'\n" > /etc/profile.d/packer.sh
  printf "alias packer /usr/local/bin/packer\n" > /etc/profile.d/packer.csh

  chcon system_u:object_r:bin_t:s0 /etc/profile.d/packer.csh
  chcon system_u:object_r:bin_t:s0 /etc/profile.d/packer.sh

}

function provide-setup() {

  # Update the System
  yum --assumeyes update

  # Install Basic Packages
  yum --assumeyes install bind-tools vim wget curl git lsof gawk nload \
    kernel-headers kernel-devel yum-plugin-fastestmirror yum-plugin-verify

  # Install the Development Tools
  # Needed to Compile VMWare/Virtualbox Kernel Modules
  yum --assumeyes groupinstall "Development Tools"

  # Create Human User If Necessary
  if [ ! -d /home/$HUMAN/ ]; then
    useradd $HUMAN
  fi
}

# Verify Root Permissions
if [[ `id --user` != 0 ]]; then
  tput setaf 1; printf "\nError. Not running with root permissions.\n\n"; tput sgr0
  exit 2
fi

# Ensure a Credentials File is Available
if [ -f $BASE/../../.credentialsrc ]; then
  source $BASE/../../.credentialsrc
else
  tput setaf 1; printf "\nError. The credentials file is missing.\n\n"; tput sgr0
  exit 2
fi

# Ensure the VMWare Serial is Available
if [ -z ${VMWARE_WORKSTATION} ]; then
  tput setaf 1; printf "\nError. The VMware serial number is missing. Add it to the credentials file.\n\n"; tput sgr0
  exit 2
fi

provide-setup
provide-limits

provide-vbox
provide-docker
provide-vmware
provide-packer
provide-libvirt

# provide-lxc
provide-vagrant

if [ -f /usr/bin/X ]; then
  provide-virtmanager
fi
