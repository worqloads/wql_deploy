#! /bin/bash
# (C) Worqloads. 2018-2020
# All rights reserved
# Licensed under Simplified BSD License (see LICENSE)
# ####################################################
# Worqloads - SmartScaler agent installation script 
# ####################################################
# Execute script with following command and target version as variable
#   WQL_VERSION=v1.0.0 bash -c "$(curl -L https://raw.githubusercontent.com/worqloads/wql_deploy/master/install.sh)"

# Initialize variables
app_folder="/app"
scaler_folder="${app_folder}/scaler"
installer_folder="${scaler_folder}/installer"
secudir=${scaler_folder}/.keys
log_file="/tmp/wql_installer_$(date "+%Y.%m.%d-%H.%M.%S").log"
git_user="hnltcs"
wql_user=`whoami`
wql_group=`id -gn`
# ####################################################

# stop if there's an error
set -e

# check prereqs & update
# Supported distrib (ubuntu, redhat) and archi (64bits)
OS=""
UNAME_M=$(uname -m)
if [[ "$UNAME_M" != "x86_64" ]]; then
    echo " Only x86_64 architecture is supported."
    exit 1
fi

if [[ $(lsb_release -d 2>/dev/null | grep -Eo Ubuntu) == "Ubuntu" ]]; then
    OS="Ubuntu"
elif [[ -f /etc/redhat-release && $(grep -Eo "Red Hat Enterprise Linux" /etc/redhat-release) == "Red Hat Enterprise Linux" ]]; then
    OS="RedHat"
elif [[ -f /etc/os-release && $(grep -E "^NAME=" /etc/os-release) == "NAME=\"Amazon Linux\"" ]]; then
    OS="AmazonLinux"
elif [[ -f /etc/os-release && $(grep -E "^NAME=" /etc/os-release) == "NAME=\"SLES\"" ]]; then
    OS="SLES"
fi

# Install packages on supported OS
if [[ $OS != "RedHat" && $OS != "Ubuntu" && $OS != "AmazonLinux" && $OS != "SLES"  ]]; then
    echo " OS not supported by SmartScaler agent. Please use one of following options: Ubuntu, SLES, RHEL or Amazon Linux."
    exit 1
fi

# ####################################################
echo " + Installing Agent App Version: $WQL_VERSION"

# Root user detection
if [[ $(echo "$UID") = "0" ]]; then
    sudo_cmd=''
else
    sudo_cmd='sudo'
fi

pckg_mngr=''
nodesource=''
echo '' > ${log_file}

if [[ $OS = "RedHat" ]]; then

    # Versions of yum on RedHat 5 and lower embed M2Crypto with SSL that doesn't support TLS1.2
    REDHAT_MAJOR_VERSION=$(grep -Eo "[0-9].[0-9]{1,2}" /etc/redhat-release | head -c 1)

    if [[ $REDHAT_MAJOR_VERSION == "" || $REDHAT_MAJOR_VERSION -lt 7 ]]; then
        echo " Only RHEL versions >= 7 are supporrted."
        exit 1
    fi

    pckg_mngr='yum'
    nodesource='https://rpm.nodesource.com/setup_12.x'

    # Only for RHEL:
    # SElinux prevent restart of pm2 due to access of .pm2/pid files in /home folders
    # dynamic change
    sudo setenforce 0
    # permanent required in case of reboot
    sudo sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config

elif [[ $OS = "Ubuntu" ]]; then
    
    if [[ -f /etc/lsb-release ]]; then
        UBUNTU_MAJOR_VERSION=$(lsb_release -sr | grep -Eo "^[0-9]{1,2}")
    fi

    if [[ $UBUNTU_MAJOR_VERSION == "" || $UBUNTU_MAJOR_VERSION -lt 18 ]]; then
        echo " Only Ubuntu versions >= 18 are supporrted."
        exit 1
    fi
    pckg_mngr='apt-get'
    nodesource='https://deb.nodesource.com/setup_12.x'

elif [[ $OS = "AmazonLinux" ]]; then
    pckg_mngr='yum'
    nodesource='https://rpm.nodesource.com/setup_12.x'
elif [[ $OS = "SLES" ]]; then

    if [[ $(grep -E "^VERSION=" /etc/os-release) != "VERSION=\"15-SP1\"" || $(getconf LONG_BIT) != 64 ]]; then
        echo " Only SLES versions >= 15 SP1 and 64 bits are supporrted."
        exit 1
    fi
    pckg_mngr='zypper'

fi

if [[ $OS = "SLES" ]]; then
    if [[ $(zypper repos | grep -c devel_languages_nodejs) == 0 ]]; then
        yes | sudo -i zypper addrepo https://download.opensuse.org/repositories/devel:/languages:/nodejs/SLE_15_SP1/devel:languages:nodejs.repo &>> ${log_file}
    fi
    yes | sudo -i zypper refresh  &>> ${log_file}
    yes | sudo -i zypper install nodejs12 &>> ${log_file}
    yes | sudo -i zypper install git                                                                     &>> ${log_file}
    node -v  &>> ${log_file}
else
    # install NodeJS, NPM, PM2, GIT
    yes | $sudo_cmd $pckg_mngr update                                                                               &>> ${log_file}
    yes | $sudo_cmd $pckg_mngr install curl git                                                                     &>> ${log_file}
    curl -sL $nodesource | $sudo_cmd -E bash -                                                                      &>> ${log_file}
    yes | $sudo_cmd $pckg_mngr install -y nodejs                                                                    &>> ${log_file}
fi

yes | $sudo_cmd npm install npm@latest -g                                                                &>> ${log_file}
yes | $sudo_cmd npm install pm2 -g                                                                       &>> ${log_file}

[[ -d ~/.ssh ]] || mkdir ~/.ssh && chmod 700  ~/.ssh                                                     &>> ${log_file}
[[ -d ~/.npm ]] && $sudo_cmd chown -R $wql_user:$wql_group ~/.npm                                         &>> ${log_file}
[[ -d ~/.config ]] && $sudo_cmd chown -R $wql_user:$wql_group ~/.config                                   &>> ${log_file}

# add cron housekeeping script of pm2 logs
pm2 install pm2-logrotate                              &>> ${log_file}
pm2 set pm2-logrotate:max_size 100M                    &>> ${log_file}
pm2 set pm2-logrotate:retain 24                        &>> ${log_file}
pm2 set pm2-logrotate:rotateInterval '0 * * * *'       &>> ${log_file}

[[ -d ${app_folder} ]] || $sudo_cmd mkdir -p ${app_folder}                                               &>> ${log_file}
$sudo_cmd chown -R $wql_user:$wql_group ${app_folder}                                                     &>> ${log_file}

# update profile
[[ `cat ~/.bashrc | grep -c '^export SECUDIR='` -ne 0  ]] || echo export SECUDIR=${secudir} >> ~/.bashrc ; export SECUDIR=${secudir}
[[ `cat ~/.bashrc | grep -c '^export NODE_ENV='` -ne 0  ]] || echo export NODE_ENV='production' >> ~/.bashrc ; export NODE_ENV='production'
[[ -f ~/.profile ]] && [[ `cat ~/.profile | grep -c '^export SECUDIR='` -ne 0  ]] || echo export SECUDIR=${secudir} >> ~/.profile
[[ -f ~/.profile ]] && [[ `cat ~/.profile | grep -c "^export NODE_ENV="` -ne 0  ]] || echo export NODE_ENV='production' >> ~/.profile 

# if $scaler_folder already exists, do a backup
[[ -d $scaler_folder ]] && $sudo_cmd mv $scaler_folder "${scaler_folder}_$(date "+%Y.%m.%d-%H.%M.%S")"   &>> ${log_file}
$sudo_cmd rm -rf ${installer_folder}
git clone https://github.com/worqloads/wql_installer.git $installer_folder                          &>> ${log_file}

cd ${installer_folder}
[[ ! -z "$WQL_VERSION" ]] && git checkout ${WQL_VERSION}                                            &>> ${log_file}
$sudo_cmd npm install                                                                                    &>> ${log_file}
[[ -d ${secudir} ]] || mkdir -p ${secudir}                                                          &>> ${log_file}
$sudo_cmd chown -R $wql_user:$wql_group ${app_folder}                                                     &>> ${log_file}

# get aws instance region
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` &>> ${log_file}
[[ -z $TOKEN ]] || awsregion=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone) && echo -n ${awsregion::-1} > ${installer_folder}/.aws_region
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id > ${installer_folder}/.aws_instanceid
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type > ${installer_folder}/.aws_instancetype
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs > ${installer_folder}/.aws_mac
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(cat ./.aws_mac)/vpc-id > ${installer_folder}/.aws_vpc
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/hostname > ${installer_folder}/.aws_hostname
[[ -z $TOKEN ]] || curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4 > ${installer_folder}/.aws_ip

[[  -f ${installer_folder}/.aws_region && \
    -f ${installer_folder}/.aws_instanceid && \
    -f ${installer_folder}/.aws_vpc && \
    -f ${installer_folder}/.aws_instancetype && \
    -f ${installer_folder}/.aws_hostname && \
    -f ${installer_folder}/.aws_ip ]] || exit 2
# create local configuration
clear
node register_min.js ${WQL_VERSION}

# registration successful
if [[ $? -eq 0 && -f './conf.json' ]]; then
    cd ${scaler_folder}
    mv ${installer_folder}/scale*min.js ${installer_folder}/node_modules ${installer_folder}/.aws_* ${installer_folder}/.ecosystem.config.js ${installer_folder}/conf.json ${scaler_folder}/    &>> ${log_file}
    # download update script
    curl -s -o ${scaler_folder}/update.sh "https://raw.githubusercontent.com/worqloads/wql_deploy/master/scripts/update.sh" && \
        chmod 700 ${scaler_folder}/update.sh &>> ${log_file}
    
    pm2 delete all &>> ${log_file} || echo ''
    pm2 flush all &>> ${log_file}
    pm2 start ${scaler_folder}/.ecosystem.config.js &>> ${log_file} || echo ''
    pm2 save &>> ${log_file}

fi

# pm2 as startup
$(pm2 startup | tail -1) &>> ${log_file}
# $sudo_cmd env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ${wql_user} --hp /home/${wql_user} &>> ${log_file}
$sudo_cmd systemctl status pm2-${wql_user}.service &>> ${log_file}

rm -rf ${installer_folder}/