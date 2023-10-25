
provider "azurerm" {
  features {}
  }

resource "azurerm_resource_group" "ansible" {
  name     = var.resource_group_name
  location = "Canada Central"
}

resource "azurerm_virtual_network" "ans-vnet" {
  name                = "ansible-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "ans-sub" {
  name                 = "ansible-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.ans-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "ansible-nsg" {
  name                = "ansible-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_public_ip" "ansible-pub" {
  count               = 1
  name                = "ansible-publicip-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "ans-nic" {
  count               = 3
  name                = "ansible-nic-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ansible-ipconfig"
    subnet_id                     = azurerm_subnet.ans-sub.id
    public_ip_address_id          = count.index == 0 ? azurerm_public_ip.ansible-pub[0].id : null
    private_ip_address_allocation = "Dynamic"
  }
}

resource "null_resource" "configure_ansible_master" {
    connection {
        host        = azurerm_linux_virtual_machine.ansible-vm[0].public_ip_address
        user        = azurerm_linux_virtual_machine.ansible-vm[0].admin_username
        password    = azurerm_linux_virtual_machine.ansible-vm[0].admin_password
        type        = "ssh"
        timeout     = "1m"
    }
  provisioner "remote-exec" {
    inline = [
      "echo '${azurerm_network_interface.ans-nic[0].private_ip_address} ansible-master' | sudo tee -a /etc/hosts",
      "echo '${azurerm_network_interface.ans-nic[1].private_ip_address} ansible-vm-1' | sudo tee -a /etc/hosts",
      "echo '${azurerm_network_interface.ans-nic[2].private_ip_address} ansible-vm-2' | sudo tee -a /etc/hosts",
      "sudo apt update",
      "sudo apt install -y software-properties-common",
      "sudo apt install -y ansible",
      "sudo sed -i 's/#inventory = /inventory = \\/etc\\/ansible\\/hosts/g' /etc/ansible/ansible.cfg",
      "echo '[ansible-master]' | sudo tee -a /etc/ansible/hosts",
      "echo '${azurerm_linux_virtual_machine.ansible-vm[0].private_ip_address} ansible_connection=ssh ansible_user=${azurerm_linux_virtual_machine.ansible-vm[0].admin_username}' | sudo tee -a /etc/ansible/hosts",
      "echo '[webservers]' | sudo tee -a /etc/ansible/hosts",
      "echo 'ansible-vm-1' | sudo tee -a /etc/ansible/hosts",
      "echo 'ansible-vm-2' | sudo tee -a /etc/ansible/hosts",
      "echo '[all:vars]' | sudo tee -a /etc/ansible/hosts",
      "echo 'ansible_python_interpreter=/usr/bin/python3' | sudo tee -a /etc/ansible/hosts",
      "sudo apt-add-repository -y --update ppa:ansible/ansible"
    ]
  }
}

resource "azurerm_linux_virtual_machine" "ansible-vm" {
  count               = 3
  name                = count.index == 0 ? "ansible-master" : "ansible-vm-${count.index}"
  computer_name       = count.index == 0 ? "ansible-master" : "ansible-vm-${count.index}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  admin_password      = "Admin123!"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.ans-nic[count.index].id,
  ]
  os_disk {
    name              = count.index == 0 ? "master-osdisk-${count.index}" : "ansible-osdisk-${count.index}"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

}


