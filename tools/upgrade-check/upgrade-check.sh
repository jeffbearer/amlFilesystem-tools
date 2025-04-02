#!/bin/bash
# 


# ==========================================
# Common Utility Functions
# ==========================================

error_exit() {
    echo "ERROR: $1"
    exit 1
}

version_gt() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]
}



# ==========================================
# Ubuntu-specific Functions
# ==========================================

check_and_install_amlfs_repo_ubuntu() {
    if ! grep -q "amlfs" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "The amlfs repository is not installed on this system."
        echo "To install the amlfs repository for Ubuntu, run the following commands:"
        echo "1. Update the package list and install required packages:"
        echo "   sudo apt update && sudo apt install -y ca-certificates curl apt-transport-https lsb-release gnupg"
        echo "2. Add the amlfs repository:"
        echo "   source /etc/lsb-release"
        echo "   echo \"deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-\${DISTRIB_CODENAME}/ \${DISTRIB_CODENAME} main\" | sudo tee /etc/apt/sources.list.d/amlfs.list"
        echo "3. Import the Microsoft GPG key:"
        echo "   curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null"
        echo "4. Update the package list:"
        echo "   sudo apt update"
        exit
    fi
}

get_available_kernels_ubuntu() {
    # This routine returns a list of kernels that are avaialable for the host.
    # It takes into account any kernel metapackages that may limit the kernels based on policy
    
    local kernel_family=$(uname -r | sed 's/^[0-9]*\.[0-9]*\.[0-9]*-//; s/^[0-9]*-//')

    # Check if a kernel metapackage is installed
    local kernel_metapackage=""
    local installed_kernels=$(dpkg-query -W -f='${binary:Package}\n' 'linux-image-*')
    for package in $installed_kernels; do
        if apt-cache show "$package" | grep -q 'Section: metapackages'; then
            kernel_metapackage="$package"
            break
        fi
    done

    if [ -n "$kernel_metapackage" ]; then
        # If a kernel metapackage is installed, restrict the list based on its policy
        latest_minor_version=$(apt-cache policy "$kernel_metapackage" | grep -A 100 'Candidate:' | grep -oP "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        apt-cache search linux-image | grep -oP "linux-image-${latest_minor_version}-[0-9a-zA-Z\-]+" | grep -- "-${kernel_family}$" | sort -V
    else
        # If no metapackage is installed, list all available kernels for the family
        apt-cache search linux-image | grep -oP "linux-image-\K[0-9]+\.[0-9]+\.[0-9]+-[0-9a-zA-Z\-]+" | grep -- "-${kernel_family}$" | sort -V
    fi
}

get_latest_lustre_kmod_ubuntu() {
    local available_kernels=$(get_available_kernels_ubuntu | sort -Vr)
    for kernel in $available_kernels; do
        kernel_version=$(echo "$kernel" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9a-zA-Z\-]+')
        local kmod=$(apt-cache search kmod-lustre-client | grep -oP "kmod-lustre-client-${kernel_version}-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-z]{8}" | sort -V | tail -1)
        if [ -n "$kmod" ]; then
            echo "$kmod"
            break
        fi
    done

    if [ -z "$kmod" ]; then
        echo "No matching Lustre kernel module found for any available kernels."
    fi
}

provide_ubuntu_commands() {

    # Collect Kernel Information
    ubuntu_version=$(lsb_release -cs)    
    current_kernel=$(uname -r | grep -oP '([0-9]+\.)?[0-9]+\.[0-9]+\.[0-9]+\-[0-9a-zA-Z\-]+')
    kernel_family=$(uname -r | sed 's/^[0-9]*\.[0-9]*\.[0-9]*-//; s/^[0-9]*-//')
    installed_kernels=$(dpkg-query -W -f='${binary:Package}\n' 'linux-image-*')
 
    # Check if a newer kernel is installed but not running
    newer_kernel_installed=false
    for kernel in $installed_kernels; do
        kernel_version=$(echo "$kernel" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9a-zA-Z\-]+')
        if dpkg --compare-versions "$kernel_version" "gt" "$current_kernel"; then
            reboot_kernel=$kernel_version
            newer_kernel_installed=true
            break
        fi
    done

    latest_kernel=$(get_available_kernels_ubuntu | grep -oP '([0-9]+\.)?[0-9]+\.[0-9]+\.[0-9]+\-[0-9a-zA-Z\-]+' | sort -V | tail -1)
    latest_kernel_with_kmod=$(get_latest_lustre_kmod_ubuntu | grep -oP "[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+\-[0-9a-zA-Z]+" | sort -V | tail -1
)

    # Check if the current kernel is ahead of the latest kernel with a published kmod
    if [ -n "$latest_kernel_with_kmod" ] && dpkg --compare-versions "$current_kernel" "gt" "$latest_kernel_with_kmod"; then
        echo "The current kernel ($current_kernel) is newer than the latest kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
        echo "To downgrade to the latest kernel with a published kernel module ($latest_kernel_with_kmod):"
        echo "1. Install the kernel package:"
        echo "   sudo apt-get install linux-image-$latest_kernel_with_kmod"
        echo "2. Configure the system to boot into the downgraded kernel:"
        echo "   sudo grub-set-default \"\$(grep -F \"\$(uname -r)\" /boot/grub/grub.cfg | head -1 | awk -F\"'\" '{print \$2}')\""
        echo "3. Reboot into the downgraded kernel:"
        echo "   sudo reboot"
        echo "4. After rebooting, run this scrupt again."
        exit
    fi

    if [ -n "$latest_kernel" ] && [ -n "$latest_kernel_with_kmod" ]; then
        if dpkg --compare-versions "$latest_kernel" "gt" "$latest_kernel_with_kmod"; then
            echo "The latest kernel ($latest_kernel) does not yet have a Lustre kernel module published at packages.microsoft.com."
            echo "Please check again in 1 to 2 business days for the Lustre kernel module to be published."
            echo "The directions provided next will get you on the latest kernel ($latest_kernel_with_kmod) that has a Lustre kernel module published."

        fi
    else
        echo "Unable to determine the latest kernel or the latest kernel with a Lustre kernel module."
    fi

    # Check if the current Lustre version is the newest
    current_lustre=$(dpkg-query -W -f='${binary:Package}\n' 'amlfs-lustre-client-*' | grep -oP '\d+\.\d+\.\d+-\d+-[0-9a-z]{8}' | sort -V | tail -1)
    latest_lustre_version=$(apt-cache search amlfs-lustre-client | grep -oP 'amlfs-lustre-client-\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-z]{8}' | sort -V | tail -1)
    if [ "$current_lustre" != "$latest_lustre_version" ]; then
        echo "The Lustre version installed on this system ($current_lustre) is not the newest."
        echo "It is reccommended that you update your Lustre client version"
        echo "To upgrade to the latest Lustre version ($latest_lustre_version):"
        echo "1. Install the package:"
        echo "   sudo apt-get -y install amlfs-lustre-client-$latest_lustre_version"
        echo "3. Resolve any dependencies:"
        echo "   sudo apt-get -f install"
    else
        echo "The current Lustre version ($current_lustre) is up-to-date."
    fi

    # Provide directions to upgrade the kernel and Lustre kernel module
    if [ -n "$latest_kernel_with_kmod" ]; then
        if [ "$current_kernel" != "$latest_kernel_with_kmod" ]; then
            echo "The current kernel ($current_kernel) does not match the latest available kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
            echo "To upgrade to the latest available kernel with a published kernel module ($latest_kernel_with_kmod):"
            echo "1. Install the latest kernel package:"
            echo "   sudo apt-get install linux-image-$latest_kernel_with_kmod"
            echo "2. Install the corresponding Lustre kernel module:"
            echo "   sudo apt-get install kmod-lustre-client-${latest_kernel_with_kmod}-${latest_lustre_version}"
            echo "3. Resolve any dependencies:"
            echo "   sudo apt-get -f install"
            echo "4. Reboot into the new kernel:"
            echo "   sudo reboot"
        else
            echo "The current kernel ($current_kernel) already matches the latest kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
        fi
    else
        echo "No Lustre kernel module is available for the latest kernel. Please check again later."
    fi
  
}

# ==========================================
# RHEL-specific Functions
# ==========================================

check_and_install_amlfs_repo_rhel() {
    if ! yum repolist | grep -q "amlfs"; then
        echo "The amlfs repository is not installed on this system."
        rhel_version=$(rpm -q --queryformat '%{VERSION}' $(rpm -q --whatprovides redhat-release))
        case $rhel_version in
            7*)
                DISTRIB_CODENAME=el7
                ;;
            8*)
                DISTRIB_CODENAME=el8
                ;;
            9*)
                DISTRIB_CODENAME=el9
                ;;
            *)
                echo "Unsupported RHEL version: $rhel_version. Please check the documentation for manual setup."
                return
                ;;
        esac

        echo "To install the amlfs repository for RHEL $rhel_version, run the following commands:"
        echo "1. Import the Microsoft GPG key:"
        echo "   sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc"
        echo "2. Add the amlfs repository:"
        echo "   sudo bash -c 'cat > /etc/yum.repos.d/amlfs.repo <<EOF"
        echo "[amlfs]"
        echo "name=Azure Lustre Packages"
        echo "baseurl=https://packages.microsoft.com/yumrepos/amlfs-${DISTRIB_CODENAME}"
        echo "enabled=1"
        echo "gpgcheck=1"
        echo "gpgkey=https://packages.microsoft.com/keys/microsoft.asc"
        echo "EOF'"
        exit
    fi
}

provide_rhel_commands() {

    # Collect Kernel Information
    current_kernel=$(uname -r | grep -oP '([0-9]+\.)?[0-9]+\.[0-9]+-[0-9a-zA-Z\.\-\_]+' | sed 's/\.[^.]*$//')
    current_kernel_dotted=$(echo "$current_kernel" | tr '_-' '.')

    # Get installed kernels
    installed_kernels=$(rpm -q kernel | sed 's/kernel-//')

    # Determine latest available kernel
    latest_kernel=$(yum --showduplicates list kernel | grep -oP '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9a-zA-Z\.]+\.el[0-9](_[0-9]+)?' | sort -V | tail -1)
    latest_kernel_dotted=$(echo "$latest_kernel" | tr '_-' '.')

    # Determine latest kernel with published Lustre kmod
    latest_kernel_with_kmod=$(yum search kmod-lustre-client | grep -oP "\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.el[0-9]+\.[0-9]" | sort -V | tail -1)

    # Check to make sure the host isn't already ahead of the latest kernel with a kmod
    if [ "$(printf '%s\n' "$current_kernel_dotted" "$latest_kernel_with_kmod" | sort -Vr | head -1)" = "$current_kernel_dotted" ] && [ "$current_kernel_dotted" != "$latest_kernel_with_kmod" ]; then
        echo "The current kernel ($current_kernel) is newer than the latest kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
        echo "To downgrade to the latest kernel with a published kernel module ($latest_kernel_with_kmod):"
        echo "1. Install the kernel package:"
        echo "   sudo yum install kernel-$latest_kernel_with_kmod"
        echo "2. Install the corresponding Lustre kernel module:"
        echo "   sudo yum install kmod-lustre-client-${latest_kernel_with_kmod}-${latest_lustre_version}"
        echo "3. Configure the system to boot into the desired kernel:"
        echo "   sudo grub2-set-default \"$(sudo grub2-mkconfig -o /boot/grub2/grub.cfg | grep -B1 \"$latest_kernel_with_kmod\" | head -1 | awk -F\' '{print $2}')\""
        echo "4. Reboot into the downgraded kernel:"
        echo "   sudo reboot"
        echo "5. After rebooting, run this scrupt again."
        exit
    fi
    
        # Check if latest kernel has a published kmod
    if [ -n "$latest_kernel_dotted" ] && [ -n "$latest_kernel_with_kmod" ]; then
        if [ "$latest_kernel_dotted" != "$latest_kernel_with_kmod" ]; then
            echo "The latest kernel ($latest_kernel) does not yet have a Lustre kernel module published at packages.microsoft.com."
            echo "Please check again in 1 to 2 business days for the Lustre kernel module to be published."
            echo "The directions provided next will get you on the latest kernel ($latest_kernel_with_kmod) that has a Lustre kernel module published."
        fi
    else
        echo "Unable to determine the latest kernel or the latest kernel with a Lustre kernel module."
    fi

    # Check current Lustre client version
    current_lustre=$(rpm -qa amlfs-lustre-client-\* | grep -oP '[0-9]+\.[0-9]+\.[0-9]+_[0-9]+_[0-9a-z]{8}' | sort -V | tail -1)
    latest_lustre_version=$(yum search amlfs-lustre-client | grep -oP 'amlfs-lustre-client-\K[0-9]+\.[0-9]+\.[0-9]+_[0-9]+_[0-9a-z]{8}' | sort -V | tail -1)

    if [ -z "$current_lustre" ]; then
        echo "No Lustre client is currently installed on this system."
        echo "To install the latest Lustre client version ($latest_lustre_version):"
        echo "1. Install the package:"
        echo "   sudo yum install amlfs-lustre-client-$latest_lustre_version"
        exit
    fi

    if [ "$current_lustre" != "$latest_lustre_version" ]; then
        echo "The Lustre version installed on this system ($current_lustre) is not the newest."
        echo "It is recommended that you update your Lustre client version."
        echo "To upgrade to the latest Lustre version ($latest_lustre_version):"
        echo "1. Install the package:"
        echo "   sudo yum install amlfs-lustre-client-$latest_lustre_version"
    else
        echo "The current Lustre version ($current_lustre) is up-to-date."
    fi

    # Provide directions to upgrade the kernel and Lustre kernel module
    if [ -n "$latest_kernel_with_kmod" ]; then
        if [ "$current_kernel_dotted" != "$latest_kernel_with_kmod" ]; then
            echo "The current kernel ($current_kernel) does not match the latest available kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
            echo "To upgrade to the latest available kernel with a published kernel module ($latest_kernel_with_kmod):"
            echo "1. Install the latest kernel package:"
            echo "   sudo yum install kernel-$latest_kernel_with_kmod"
            echo "2. Install the corresponding Lustre kernel module:"
            echo "   sudo yum install kmod-lustre-client-${latest_kernel_with_kmod}-${latest_lustre_version}"
            echo "3. Reboot into the new kernel:"
            echo "   sudo reboot"
        else
            echo "The current kernel ($current_kernel) already matches the latest kernel with a Lustre kernel module ($latest_kernel_with_kmod)."
        fi
    else
        echo "No Lustre kernel module is available for the latest kernel. Please check again later."
    fi
}


# ==========================================
# Main Execution Logic
# ==========================================

main() {
    if [ -f /etc/redhat-release ]; then
        check_and_install_amlfs_repo_rhel
        provide_rhel_commands
    elif [ -f /etc/lsb-release ]; then
        check_and_install_amlfs_repo_ubuntu
        provide_ubuntu_commands
    else
        error_exit "Unsupported operating system."
    fi
}

main "$@"