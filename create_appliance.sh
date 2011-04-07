#!/bin/bash
# ============================================================================
# Script for creating appliances exported from SUSE Studio
# (http://susestudio.com) on your local system.
#
# Requires kiwi (http://kiwi.berlios.de/).
#
# Author:  James Tan <jatan@suse.de>
# Contact: feedback@susestudio.com
# ============================================================================

# Recover backup files 
function recover_backup {
  for dir in 'bootsource' 'source'; do
    if [ -f $dir/config.xml.bak ]; then
      cp $dir/config.xml.bak $dir/config.xml
      echo "  -> Recovered Backup $dir/config.xml.bak to $dir/config.xml"
    fi
  done
}

# Prints and runs the given command. Aborts if the command fails.
function run_cmd {
  command=$1
  logfile=$2
  echo $command
  $command
  if [ $? -ne 0 ]; then
    echo
    echo "** Appliance creation failed!"
    while true; do
      read -p "Recover config.xml files? [y/n] " yn
      case $yn in
        [Nn]* ) break;;
        [Yy]* ) recover_backup;break;;
     esac
    done

    if [ "$logfile" != '' ]; then
      echo "See $logfile for details."
    fi
    exit 1
  fi
}

# Display usage.
function usage {
  echo >&2 "Usage:"
  echo >&2 "  create_appliance.sh [--no-custom-boot-image]"
}

# Parse command line options.
no_custom_boot_image=
while [ $# -gt 0 ]; do
  case "$1" in
    --no-custom-boot-image) no_custom_boot_image=true;;
    -*) usage; exit 1;;
    *) break;;
  esac
  shift
done

# Check that we're root.
if [ `whoami` != 'root' ]; then
  echo "Please run this script as root."
  exit 1
fi

# Check that kiwi is installed.
kiwi=`which kiwi 2> /dev/null`
if [ $? -ne 0 ]; then
  echo "Kiwi is required but not found on your system."
  echo "Run the following command to install kiwi:"
  echo
  echo "  zypper install kiwi kiwi-tools kiwi-desc-* kiwi-doc"
  echo
  exit 1
fi

# Check kiwi version.
kiwi_ver='kiwi-4.80-8.1'
installed_kiwi_ver=`rpm -q kiwi`
if [ "$installed_kiwi_ver" != "$kiwi_ver" ]; then
  echo "'$kiwi_ver' expected, but '$installed_kiwi_ver' found."
  while true; do
    read -p "Continue? [y/n] " yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit;;
    esac
  done
fi

# Check architecture (i686, x86_64).
image_arch='i686'
sys_arch=`uname -m`
linux32=`which linux32 2>/dev/null`
if [ "$image_arch" = 'i686' ] && [ "$sys_arch" = 'x86_64' ]; then
  if [ "$linux32" = '' ]; then
    echo "'linux32' is required but not found."
    exit 1
  else
    kiwi="$linux32 $kiwi"
  fi
elif [ "$image_arch" = 'x86_64' ] && [ "$sys_arch" = 'i686' ]; then
  echo "Cannot build $image_arch image on a $sys_arch machine."
  exit 1
fi

# Replace internal repositories in config.xml.
echo "** Checking for internal repositories..."
for repo in "itomato openSUSE 11.1" "itomato openSUSE 11.2"; do
  # check if the repos are already replaced
  update_repo=0
  for dir in 'bootsource' 'source'; do
    grep -q "{$repo}" $dir/config.xml && update_repo=1
  done

  if [ $update_repo -eq 1 ]; then
    # prompt for repo url
    read -p "Enter repository URL for '$repo': " url
    escaped_url=`echo "$url" | sed -e 's/\//\\\\\//g'`
    for dir in 'bootsource' 'source'; do
      # backup config.xml first
      if [ ! -f $dir/config.xml.bak ]; then
        cp $dir/config.xml $dir/config.xml.bak
        echo "  -> Backed up $dir/config.xml to $dir/config.xml.bak"
      fi
      sed -i "s/{$repo}/$escaped_url/g" $dir/config.xml
    done
  fi
done

# Get the build profiles from config.xml
echo
echo "** Fetching boot profiles..."

profiles_line=$(grep -m 1 -E "<type.*?boot(profile|kernel).*?>" source/config.xml)
bootprofile=$(echo $profiles_line | grep -oE "bootprofile='\w+'" | sed -e "s/'//g" | awk -F "=" '{ print $2 }')
bootkernel=$(echo $profiles_line | grep -oE "bootkernel='\w+'" | sed -e "s/'//g" | awk -F "=" '{ print $2 }')

if [ "$bootprofile" != '' ]; then
  echo "Using boot profile $bootprofile"
else
  echo "Using default boot profile" 
fi

if [ "$bootkernel" != '' ]; then
  echo "Using boot kernel $bootkernel"
else
  echo "Using default boot kernel" 
fi

# Create boot image (with custom theming).
if [ ! "$no_custom_boot_image" ]; then
  echo
  echo "** Creating custom boot image (initrd)..."
  run_cmd "rm -rf bootbuild/root bootimage/initrd"
  run_cmd "mkdir -p bootbuild bootimage/initrd"

  prepare_log='boot-prepare.log'
  create_log='boot-create.log'
  
  prepare_opts="--prepare bootsource --root bootbuild/root --logfile $prepare_log"
  create_opts="--create bootbuild/root -d bootimage/initrd --logfile $create_log"

  if [ "$bootkernel" != '' ]; then
    prepare_opts="$prepare_opts --add-profile $bootkernel"
    create_opts="$create_opts --add-profile $bootkernel"
  fi

  if [ "$bootprofile" != '' ]; then
    prepare_opts="$prepare_opts --add-profile $bootprofile"
    create_opts="$create_opts --add-profile $bootprofile"
  fi

  run_cmd "$kiwi $prepare_opts" $prepare_log
  run_cmd "$kiwi $create_opts" $create_log
fi

# Create appliance with custom initrd.
echo
echo "** Creating appliance..."
run_cmd "rm -rf build/root"
run_cmd "mkdir -p build image"

log='prepare.log'
run_cmd "$kiwi --prepare source --root build/root --logfile $log" $log

log='create.log'
run_cmd "$kiwi --create build/root -d image --prebuiltbootimage bootimage/initrd \
               --logfile $log" $log

# And we're done!
image_file="image/zDev_11.4.i686-0.1.10.vmdk"
qemu_options='-snapshot'
[[ "$image_file" =~ \.iso$ ]] && qemu_options='-cdrom'
echo
echo "** Appliance created successfully! ($image_file)"
echo "To boot the image using qemu-kvm, run the following command:"
echo "  qemu-kvm -m 512 $qemu_options $image_file &"
echo
