# -*- mode: ruby -*-
# vi: set ft=ruby :

$script = <<SCRIPT
# Put the host machine's IP into the authorised_keys file on the VM
if [ -r /vagrant/id_rsa.pub ]; then
        mkdir -p $HOME/.ssh && cat /vagrant/id_rsa.pub >> $HOME/.ssh/authorized_keys
fi
SCRIPT

# 2 = version of configuration file for Vagrant 1.1+ leading up to 2.0.x
Vagrant.configure("2") do |config|

  config.vm.define :adoptopenjdkF38 do |adoptopenjdkF38|
    adoptopenjdkF38.vm.box = "bento/fedora-38"
    adoptopenjdkF38.vm.synced_folder ".", "/vagrant"
    adoptopenjdkF38.vm.hostname = "adoptopenjdkF38"
    adoptopenjdkF38.vm.network :private_network, type: "dhcp"
    adoptopenjdkF38.vm.provision "shell", inline: $script, privileged: false
  end
  config.vm.provider "virtualbox" do |v|
    v.gui = false
    v.memory = 4196
    v.customize ["modifyvm", :id, "--cpuexecutioncap", "50"]
  end
end
