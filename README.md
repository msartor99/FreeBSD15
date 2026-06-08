# FreeBSD 15 post installation

Installing FreeBSD is simple, but configuring it for everyday use is a bit more complex.

I consulted numerous websites, forums, and YouTube videos to find the optimal configuration.

working with Gemini for best interactivity

Here is the latest version of the installation script.


Launch PuTTY to connect to an SSH session over the network as root or your user and type su - to connect root.

type:

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/refs/heads/main/FreeBSD_15_universal_post_install.sh

sh FreeBSD_15_universal_post_install.sh

Enjoy!

# 8 june 2026 New version

Complete overhaul of the post-installation script; the new script is post_install_latest.sh

fetch https://raw.githubusercontent.com/msartor99/FreeBSD15/7cbe8ebefab0945ccbd1b3e6f985e92a7e2c1c60/post_install_latest.sh

chmod +x post_install_latest.sh

./post_install_latest.sh





# 23 april 2026 New version
________________________________________________________________________________________

here is a new version : FreeBSD_15_universal_post_install.sh

some enhancement and adjustment.


Enjoy!

# new script to switch X11 to Wayland for Nvidia graphic card

symply, a switch to install wayland after X11 installation.

This script installs Wayland, configures it, tests the latest version of the Nvidia drivers, and sets up the driver. Currently, the Nvidia driver crashes the system, but since Nvidia driver development is constantly evolving, I hope future versions will work. In the meantime, this script creates the necessary configuration for Wayland to function on Nvidia. This script checks the current configuration and modifies it without creating duplicates.

switch_to_wayland.sh

# new script to install mwm and all configuration theme for IRIX clone

install_irix_clone.sh

Enjoy !


# new script to install mwm and all configuration theme for SCO Unix clone

install_sco_theme.sh

Enjoy !
