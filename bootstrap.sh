#!/bin/bash -uxe
# A bash script that prepares the OS
# before running the Ansible playbook

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
else
	echo "This installer seems to be running on an unsupported distribution.
Supported distros are Ubuntu 20.04 and 22.04"
	exit
fi

if [[ "$os" == "ubuntu" && "$os_version" -lt 2004 ]]; then
	echo "Ubuntu 20.04 or higher is required to use this installer.
This version of Ubuntu is too old and unsupported."
	exit
fi


# root or not
if [[ $EUID -ne 0 ]]; then
  SUDO='sudo -H -E'
else
  SUDO=''
fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt update -y;
$SUDO yes | apt-get -o Dpkg::Options::="--force-confold" -fuy dist-upgrade;
$SUDO yes | apt-get -o Dpkg::Options::="--force-confold" -fuy install software-properties-common curl git python3 python3-setuptools python3-apt python3-pip python3-passlib python3-wheel python3-bcrypt aptitude -y;
$SUDO yes | apt-get -o Dpkg::Options::="--force-confold" -fuy autoremove;
[ $(uname -m) == "aarch64" ] && $SUDO yes | apt install gcc python3-dev libffi-dev libssl-dev make -y;

pip3 install ansible -U &&
export DEBIAN_FRONTEND=
[ -d "$HOME/ansible-easy-vpn" ] || git clone https://github.com/notthebee/ansible-easy-vpn


clear
echo "Welcome to ansible-easy-vpn!"
echo
echo "This script is interactive"
echo "If you prefer to fill in the inventory.yml file manually,"
echo "press [Ctrl+C] to quit this script"
echo
echo "Enter your desired UNIX username"
read -p "Username: " username
until [[ "$username" =~ ^[a-z0-9]*$ ]]; do
  echo "Invalid username"
  echo "Make sure the username only contains lowercase letters and numbers"
  read -p "Username: " username
done

sed -i "s/username: .*/username: ${username}/g" $HOME/ansible-easy-vpn/inventory.yml

echo
echo "Enter your user password"
echo "This password will be used for Authelia login,"
echo "administrative access and SSH login"
read -s -p "Enter your user password: " user_password

echo
echo "Enter your domain name"
echo "The domain name should already resolve to the IP address of your server"
read -p "Domain name: " root_host
until [[ "$root_host" =~ ^[a-z0-9\.]*$ ]]; do
  echo "Invalid domain name"
  read -p "Domain name: " root_host
done

sed -i "s/root_host: .*/root_host: ${root_host}/g" $HOME/ansible-easy-vpn/inventory.yml

echo
echo "Would you like to generate a new SSH key pair?"
echo "Press 'n' if you already have a public SSH key that you want to use"
read -p "[y/N]: " new_ssh_key_pair
until [[ "$new_ssh_key_pair" =~ ^[yYnN]*$ ]]; do
				echo "$new_ssh_key_pair: invalid selection."
				read -p "[y/N]: " new_ssh_key_pair
        sed -i "s/enable_ssh_keygen: .*/enable_ssh_keygen: true/g" $HOME/ansible-easy-vpn/inventory.yml
done

if [[ "$new_ssh_key_pair" =~ ^[nN]$ ]]; then
  echo
  read -p "Please enter your SSH public key: " ssh_key_pair
  sed -i "s/#+ +ssh_public_key: .*/ssh_public_key: ${ssh_key_pair}/g" $HOME/ansible-easy-vpn/inventory.yml
fi

echo
echo "Would you like to set up the e-mail functionality?"
echo "It will be used to confirm the 2FA setup,"
echo "restore the password in case you forget it,"
echo "and send you server notifications (auto-updates, banned IPs, etc.)"
echo
echo "This requires a working SMTP account (e.g. Mailbox, Tutanota, GMail)"
echo "If you use GMail, you will need to generate an application pasword"
echo "https://support.google.com/mail/answer/185833?hl=en-GB"
echo
read -p "[y/N]: " email_setup
until [[ "$email_setup" =~ ^[yYnN]*$ ]]; do
				echo "$email_setup: invalid selection."
				read -p "[y/N]: " email_setup
done

if [[ "$email_setup" =~ ^[yY]$ ]]; then
  echo
  read -p "SMTP server: " smtp_server
  until [[ "$smtp_server" =~ ^[a-z0-9\.]*$ ]]; do
    echo "Invalid SMTP server"
    read -p "SMTP server: " smtp_server
  done
  echo
  read -p "SMTP port (defaults to 465): " smtp_port
  if [ -z ${smtp_port} ]; then
    smtp_port="465"
  fi
  echo
  read -p "SMTP login: " smtp_login
  echo
  read -p -s "SMTP password: " smtp_password


  echo
  read -p -s "'From' e-mail (leave empty for SMTP login): " email
  if [ -z ${email} ]; then
    email=$smtp_login
  fi

  sed -i "s/email_smtp_host: .*/email_smtp_host: ${smtp_server}/g" $HOME/ansible-easy-vpn/inventory.yml
  sed -i "s/email_smtp_port: .*/email_smtp_port: ${smtp_port}/g" $HOME/ansible-easy-vpn/inventory.yml
  sed -i "s/email_login: .*/email_login: ${smtp_login}/g" $HOME/ansible-easy-vpn/inventory.yml
  sed -i "s/email_smtp_port: .*/email_smtp_port: ${smtp_port}/g" $HOME/ansible-easy-vpn/inventory.yml
fi

touch $HOME/ansible-easy-vpn/secret.yml
chmod 600 $HOME/ansible-easy-vpn/secret.yml
if [ -z ${smtp_password+x} ]; then
  echo
else 
  echo "email_password: ${smtp_password}" >> $HOME/ansible-easy-vpn/secret.yml
fi

echo "user_password: ${user_password}" > $HOME/ansible-easy-vpn/secret.yml

echo
echo "Encrypting the variables"
ansible-vault encrypt $HOME/ansible-easy-vpn/secret.yml