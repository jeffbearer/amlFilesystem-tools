#!/bin/bash

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <amlfs_version_index>"
    echo "  0 = latest amlfs-lustre-client"
    echo "  1 = previous version"
    echo "  2 = two versions back, etc."
    exit 1
fi

# Validate input is a number
if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Please provide a non-negative number"
    exit 1
fi

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Error: Unable to detect operating system."
    exit 1
fi


check_and_install_amlfs_repo_ubuntu() {
    if ! grep -q "amlfs" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "The amlfs repository is not installed. Installing it now..."

        # Install required packages
        sudo apt-get update -qq
        sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg

        # Add the amlfs repository
        source /etc/lsb-release
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/amlfs-${DISTRIB_CODENAME}/ ${DISTRIB_CODENAME} main" | sudo tee /etc/apt/sources.list.d/amlfs.list

        # Import the Microsoft GPG key
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

        # Update package lists
        sudo apt-get update -qq
        echo "amlfs repository installed successfully."
    else
        echo "The amlfs repository is already installed."
    fi
}


check_and_install_amlfs_repo_rhel() {
    if ! yum repolist | grep -q "amlfs"; then
        echo "The amlfs repository is not installed. Installing it now..."

        # Import the Microsoft GPG key
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

        # Determine RHEL version
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
                exit 1
                ;;
        esac

        # Add the amlfs repository
        sudo bash -c "cat > /etc/yum.repos.d/amlfs.repo <<EOF
[amlfs]
name=Azure Lustre Packages
baseurl=https://packages.microsoft.com/yumrepos/amlfs-${DISTRIB_CODENAME}
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF"

        echo "amlfs repository installed successfully."
    else
        echo "The amlfs repository is already installed."
    fi
}


# Function to handle Ubuntu kernel installation
install_amlfs_ubuntu() {
    echo "Detected Ubuntu system."

    # Update package lists
    sudo apt-get update -qq

    # Get list of available amlfs-lustre-client versions sorted in descending order
    AMLFS_LIST=($(apt-cache search '^amlfs-lustre-client-[0-9]' | awk '{print $1}' | sed 's/amlfs-lustre-client-//' | sort -V -r))

    # Check if the requested index exists
    if [ $1 -ge ${#AMLFS_LIST[@]} ]; then
        echo "Error: amlfs version index $1 is out of range. Only ${#AMLFS_LIST[@]} versions available."
        exit 1
    fi

    # Get the selected amlfs-lustre-client version
    SELECTED_VERSION=${AMLFS_LIST[$1]}

    echo "Installing amlfs-lustre-client version: $SELECTED_VERSION"

    # Install the selected amlfs-lustre-client version
    sudo apt-get install -y amlfs-lustre-client-${SELECTED_VERSION}

    echo "amlfs-lustre-client installation complete."


# Function to handle RHEL kernel installation
install_amlfs_rhel() {
    echo "Detected RHEL system."

    # Update package lists
    sudo yum check-update -q

    # Get list of available amlfs-lustre-client versions sorted in descending order
    AMLFS_LIST=($(yum list available 'amlfs-lustre-client-*' | grep '^amlfs-lustre-client-' | awk '{print $1}' | sed 's/amlfs-lustre-client-//' | sort -V -r))

    # Check if the requested index exists
    if [ $1 -ge ${#AMLFS_LIST[@]} ]; then
        echo "Error: amlfs version index $1 is out of range. Only ${#AMLFS_LIST[@]} versions available."
        exit 1
    }

    # Get the selected amlfs-lustre-client version
    SELECTED_VERSION=${AMLFS_LIST[$1]}

    echo "Installing amlfs-lustre-client version: $SELECTED_VERSION"

    # Install the selected amlfs-lustre-client version
    sudo yum install -y amlfs-lustre-client-${SELECTED_VERSION}

    echo "amlfs-lustre-client installation complete."
}

# Call the appropriate function based on the detected OS
case $OS in
    ubuntu)
        check_and_install_amlfs_repo_ubuntu
        install_amlfs_ubuntu $1
        ;;
    rhel|centos|fedora)
        check_and_install_amlfs_repo_rhel
        install_amlfs_rhel $1
        ;;
    *)
        echo "Error: Unsupported operating system: $OS"
        exit 1
        ;;
esac