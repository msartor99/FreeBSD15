# FreeBSD 15 post installation

Installing FreeBSD is simple, but configuring it for everyday use is a bit more complex.

I consulted numerous websites, forums, and YouTube videos to find the optimal configuration.

working with Gemini for best interactivity

Here is the latest version of the installation script.

FreeBSD_15_universal_post_install.sh


Launch PuTTY to connect to an SSH session as root over the network.

type:

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/refs/heads/main/FreeBSD_15_universal_post_install.sh

sh FreeBSD_15_universal_post_install.sh

Enjoy!

# New version
________________________________________________________________________________________

here is a new version : FreeBSD_15_new_univ_post_install.sh
some enhancement and adjustment
.

Enjoy!

# new script to switch X11 to Wayland

symply, a switch to install wayland after X11 installation.

This script installs Wayland, configures it, tests the latest version of the Nvidia drivers, and sets up the driver. Currently, the Nvidia driver crashes the system, but since Nvidia driver development is constantly evolving, I hope future versions will work. In the meantime, this script creates the necessary configuration for Wayland to function on Nvidia. This script checks the current configuration and modifies it without creating duplicates.

switch_to_wayland.sh

