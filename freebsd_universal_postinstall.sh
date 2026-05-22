#!/bin/sh
# ----------------------------------------------------------------------
# Script de Post-Installation Universel FreeBSD (Compatible 14.4 / 15.x)
# Auteur : msartor99
# ----------------------------------------------------------------------

# --- 0. CONFIGURATION DE BASE (CLAVIER & LANGUE) ---
echo "Configuration du clavier (Suisse Romand)..."
sysrc keymap="ch.fr.kbd"

echo "Configuration de la langue du système (fr_CH.UTF-8) pour SDDM..."
# Modification de la classe de login par défaut pour imposer la langue système
sed -i '' -e 's/:umask=022:/:umask=022:\\\n\t:charset=UTF-8:\\\n\t:lang=fr_CH.UTF-8:/g' /etc/login.conf
# Recompilation obligatoire de la base de données de connexion
cap_mkdb /etc/login.conf

# --- 1. DÉTECTION AUTOMATIQUE DE L'OS ET DU MATÉRIEL ---
FBSD_VERSION=$(freebsd-version -u | cut -d'.' -f1)
echo "Détection de FreeBSD : version majeure $FBSD_VERSION"

GPU_VENDOR="Inconnu"
if pciconf -lv | grep -iq "nvidia"; then
    GPU_VENDOR="NVIDIA"
elif pciconf -lv | grep -iq "amd"; then
    GPU_VENDOR="AMD"
elif pciconf -lv | grep -iq "intel"; then
    GPU_VENDOR="Intel"
elif pciconf -lv | grep -iq "virtio\|vmware"; then
    GPU_VENDOR="Machine Virtuelle"
fi
echo "Matériel graphique détecté : $GPU_VENDOR"
sleep 2

# --- 2. PRÉPARATION DES OUTILS ---
if ! command -v dialog >/dev/null 2>&1; then
    echo "Installation de 'dialog' pour l'interface du menu..."
    env ASSUME_ALWAYS_YES=YES pkg install dialog
fi

CHOICES_FILE=$(mktemp /tmp/fbsd_install_choices.XXXXXX)

# --- 3. MENU INTERACTIF (TUI) ---
dialog --backtitle "Configuration Post-Installation FreeBSD" \
       --title "Sélection des composants" \
       --checklist "Cochez les éléments à installer :\nOS: FreeBSD $FBSD_VERSION | GPU: $GPU_VENDOR" \
       20 75 10 \
       "1" "Environnement Graphique (Wayland/X11, Pilotes & SDDM)" on \
       "2" "Couche de compatibilité Linux" off \
       "3" "Serveur de fichiers Samba" off \
       "4" "Outils de base (git, htop, vim, sudo, curl)" on \
       "5" "Règles de sécurité (Hardening basique)" off \
       2> "$CHOICES_FILE"

clear
CHOICES=$(cat "$CHOICES_FILE")
rm -f "$CHOICES_FILE"

if [ -z "$CHOICES" ]; then
    echo "Installation annulée par l'utilisateur."
    exit 0
fi

# --- 4. EXÉCUTION DES INSTALLATIONS ---
echo "Mise à jour du catalogue de paquets..."
pkg update

for CHOICE in $CHOICES; do
    # Nettoyage des guillemets
    CHOICE=$(echo "$CHOICE" | tr -d '"')

    case "$CHOICE" in
        1)
            echo "--> Installation de l'Environnement Graphique et de SDDM..."
            if [ "$FBSD_VERSION" -ge 15 ]; then
                pkg install -y wayland seatd sddm
                sysrc seatd_enable="YES"
            else
                pkg install -y xorg sddm
            fi
            
            # Activation de SDDM
            sysrc sddm_enable="YES"
            
            # Installation et chargement des pilotes graphiques selon le matériel
            case "$GPU_VENDOR" in
                "NVIDIA") 
                    pkg install -y nvidia-driver 
                    sysrc kld_list+=" nvidia-modeset"
                    ;;
                "AMD") 
                    pkg install -y drm-kmod 
                    sysrc kld_list+=" amdgpu"
                    ;;
                "Intel")
                    pkg install -y drm-kmod
                    sysrc kld_list+=" i915kms"
                    ;;
            esac
            ;;
        2)
            echo "--> Activation de la compatibilité Linux..."
            kldload linux64
            sysrc linux_enable="YES"
            ;;
        3)
            echo "--> Installation de Samba..."
            pkg install -y samba416
            sysrc samba_server_enable="YES"
            ;;
        4)
            echo "--> Installation des outils de base..."
            pkg install -y git-lite htop vim sudo curl
            ;;
        5)
            echo "--> Application des règles de sécurité..."
            sysrc clear_tmp_enable="YES"
            sysrc syslogd_flags="-ss"
            sysrc sendmail_enable="NONE"
            ;;
    esac
done

echo "========================================="
echo "Installation terminée avec succès !"
echo "Un redémarrage du système est nécessaire."
echo "========================================="
