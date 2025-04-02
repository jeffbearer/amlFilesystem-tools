#!/bin/bash

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <kernel_index>"
    echo "  0 = latest kernel"
    echo "  1 = previous kernel"
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

# Function to handle Ubuntu kernel installation
install_kernel_ubuntu() {
    echo "Detected Ubuntu system."

    # Update package lists
    sudo apt-get update -qq

    # Get list of available kernel versions sorted in descending order
    KERNEL_LIST=($(apt-cache search --names-only '^linux-image-[0-9]' | awk '{print $1}' | grep -v 'unsigned' | sort -V -r))

    # Check if the requested index exists
    if [ $1 -ge ${#KERNEL_LIST[@]} ]; then
        echo "Error: Kernel index $1 is out of range. Only ${#KERNEL_LIST[@]} kernels available."
        exit 1
    fi

    # Get the selected kernel package name
    SELECTED_KERNEL=${KERNEL_LIST[$1]}

    echo "Installing kernel package: $SELECTED_KERNEL"

    # Install the selected kernel version
    sudo apt-get install -y $SELECTED_KERNEL

    echo "Kernel installation complete. Please reboot to use the new kernel."
}

# Function to handle RHEL kernel installation
install_kernel_rhel() {
    echo "Detected RHEL system."

    # Get list of available kernel versions sorted in descending order
    KERNEL_LIST=($(dnf --showduplicates list available kernel-core | grep kernel-core | awk '{print $2}' | sort -V -r))

    # Check if the requested index exists
    if [ $1 -ge ${#KERNEL_LIST[@]} ]; then
        echo "Error: Kernel index $1 is out of range. Only ${#KERNEL_LIST[@]} kernels available."
        exit 1
    fi

    # Get the selected kernel version
    SELECTED_VERSION=${KERNEL_LIST[$1]}

    echo "Installing kernel version: $SELECTED_VERSION"

    # Install the selected kernel version
    dnf -y install kernel-core-${SELECTED_VERSION} kernel-${SELECTED_VERSION}

    echo "Kernel installation complete. Please reboot to use the new kernel."
}

# Call the appropriate function based on the detected OS
case $OS in
    ubuntu)
        install_kernel_ubuntu $1
        ;;
    rhel|centos|fedora)
        install_kernel_rhel $1
        ;;
    *)
        echo "Error: Unsupported operating system: $OS"
        exit 1
        ;;
esac