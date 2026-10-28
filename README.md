# FreeBSD 15 post installation

Installing FreeBSD is simple, but configuring it for everyday use is a bit more complex.

I consulted numerous websites, forums, and YouTube videos to find the optimal configuration.

working with Gemini for best interactivity

Here is the latest version of the installation script.


Launch PuTTY to connect to an SSH session over the network as root or your user and type su - to connect root.



# 28 october 2026

New version of the post-installation script for FreeBSD 15.1; a complete overhaul featuring menus based on bsddialog.

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/refs/heads/main/install-workstation_v1.28.sh

chmod +x install-workstation_v1.28.sh

./install-workstation_v1.28.sh

New version of the script that compiles the NVIDIA driver and dependencies, along with Wayland, to switch to the Wayland display server.

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/refs/heads/main/enable-nvidia-wayland-v1.7.sh

chmod +x enable-nvidia-wayland-v1.7.sh

./enable-nvidia-wayland-v1.7.sh



# 8 july 2026, simple MATE desktop post installation

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/refs/heads/main/mate-post-install.sh

# 29 june 2026, new little utility to delete / create ZFS pool

zfs-setup.sh

Enjoy!

# new script to switch X11 to Wayland for Nvidia graphic card

symply, a switch to install wayland after X11 installation.

This script installs Wayland, configures it, tests the latest version of the Nvidia drivers, and sets up the driver. Currently, the Nvidia driver crashes the system, but since Nvidia driver development is constantly evolving, I hope future versions will work. In the meantime, this script creates the necessary configuration for Wayland to function on Nvidia. This script checks the current configuration and modifies it without creating duplicates.

switch_to_wayland.sh


# new script to install mwm and all configuration theme for SCO Unix clone

install_sco_theme.sh

Enjoy !
