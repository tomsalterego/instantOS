#!/usr/bin/env bash

###############################################
## script for instantOS autostart            ##
###############################################

INSTANTVERSION="$(cat /usr/share/instantutils/version)"
if iconf version && [ "$(iconf version)" = "$INSTANTVERSION" ]; then
    echo "version check successful"
    echo "running version $INSTANTVERSION"
else
    echo "running update hooks"
    /usr/share/instantutils/userinstall.sh
    iconf -i userinstall 1
    iconf version "$INSTANTVERSION"
    instantutils default
fi

# architecture detection
if [ -z "$1" ]; then
    if uname -m | grep -q '^arm'; then
        export ISRASPI=true
    fi

    if iconf -i noautostart; then
        echo "autostart disabled"
        exit
    fi

    if [ "$(ps aux | grep bash | grep instantautostart | wc -l)" -gt 3 ]; then
        echo "already running"
        exit
    fi
else
    echo "forced run"
fi

cd
command -v instantdotfiles && instantdotfiles

if ! iconf -i rangerplugins && command -v rangerplugins; then
    mkdir instantos
    echo "installing ranger plugins"
    mkdir -p ~/.config/ranger/plugins
    cp -r /usr/share/rangerplugins/* ~/.config/ranger/plugins/
    iconf -i rangerplugins 1
fi

# find out if it's a live session
if [ -e /usr/share/liveutils ] &>/dev/null; then
    ISLIVE="True"
    echo "live session detected"
fi

if iconf -i islaptop; then
    export ISLAPTOP="true"
    echo "laptop detected"
else
    echo "not a laptop"
fi

islive() {
    if [ -n "$ISLIVE" ]; then
        return 0
    else
        return 1
    fi
}

# optionally disable status bar
if iconf -i nobar; then
    NMON=$(iconf names | wc -l)
    for i in $(eval "echo {1..$NMON}"); do
        echo "found monitor $i"
        xdotool key super+comma
        xdotool key super+b
    done &
fi

if [ -n "$ISRASPI" ]; then
    # enable double drawing for moving floating windows
    # greatly increases smoothness
    iconf -i highfps 1
    if ! [ -e ~/.config/instantos/israspi ]; then
        echo "marking machine as raspi"
        mkdir -p ~/.config/instantos
        touch ~/.config/instantos/israspi
        # logo does not work on raspi
        iconf -i nologo 1
    fi
fi

if ! iconf -i notheming; then
    instantthemes a
    xrdb ~/.Xresources
    iconf -i instantthemes 1

    # dynamically switch between light and dark gtk theme
    DATEHOUR=$(date +%H)
    if [ "$DATEHOUR" -gt "20" ] || [ "$DATEHOUR" -lt "7" ]; then
        instantthemes d &
        touch /tmp/instantdarkmode
        [ -e /tmp/instantlightmode ] && rm /tmp/instantlightmode
    else
        instantthemes l &
        touch /tmp/instantlightmode
        [ -e /tmp/instantdarkmode ] && rm /tmp/instantdarkmode
    fi &
else
    touch /tmp/instantlightmode
fi

mkdir -p /tmp/notifications &>/dev/null
if ! pgrep dunst; then
    while :; do
        # wait for theming before starting dunst
        if [ -e /tmp/instantdarkmode ] || [ -e /tmp/instantlightmode ]; then
            dunst
        fi
        sleep 2
    done &
fi

onlinetrigger() {
    instantwallpaper &
}

# set up oh-my-zsh config if not existing already
iconf -i nozsh || instantshell &

# fix resolution on virtual machine
if ! iconf -i novmfix && grep -q 'hypervisor' /proc/cpuinfo; then
    # indicator file only exists on kvm/QEMU on amd
    if [ -e /opt/instantos/kvm ]; then
        iconf -i highfps 1
        if lshw -c video | grep -i 'qxl' || xrandr | grep -i '^qxl'; then
            iconf -i qxl 1
            # iconf -i noanimations 1
            if ! iconf -i potato && ! iconf -i nopotato; then
                if echo "please set your video card to virtio or passthrough
QXL on AMD on QEMU/kvm has been known to cause a severe Xorg memory leak. 
Disabling compositing makes this somewhat bearable,
but switching really is recommended.
(or switch to virtualbox, no issues there...)
Disable compositing for this VM?" | imenu -C; then
                    iconf -i potato 1
                    pkill picom
                else
                    if ! imenu -c "ask again next time?"; then
                        iconf -i nopotato 1
                    fi
                fi
            fi
        else
            iconf -i qxl 1
        fi
    fi

    if ! [ -e /opt/instantos/guestadditions ]; then
        if echo "virtual machine detected.
Would you like to switch to a 1080p resolution?" | imenu -C; then
            echo "applying virtual machine workaround"
            /usr/share/instantassist/assists/t/v.sh
        else
            if ! imenu -c "ask again next session"; then
                iconf -i novmfix 1
            fi
        fi
    fi
fi

if ! islive; then
    echo "not a live session"
    if [ -e /opt/instantos/installtrigger ]; then
        zenity --info --text "finishing installation in background" &

        # ask for password if postinstall already ran
        if ! timeout 2 sudo echo test; then
            instantsudo instantpostinstall
            sudo rm /opt/instantos/installtrigger
        else
            sudo instantpostinstall
        fi

        pkill zenity
    fi

    cd ~/instantos || exit 1
    if ! iconf -i max; then
        instantmonitor
    fi

    if [ -e ~/instantos/monitor.sh ]; then
        echo "restoring resolution"
        bash ~/instantos/monitor.sh &
    elif [ -e ~/.config/autorandr/instantos/config ]; then
        echo "restoring autorandr resolution"
        autorandr instantos &
    fi

    if checkinternet; then
        onlinetrigger
    else
        # fall back to already installed wallpapers
        instantwallpaper offline
        for i in $(seq 10); do
            if checkinternet; then
                onlinetrigger
                break
            else
                sleep 10
            fi
        done
    fi &

    # apply keybpard layout
    if iconf layout; then
        setxkbmap -layout "$(iconf layout)"
    else
        CURLOCALE=$(locale | grep LANG | sed 's/.*=\(.*\)\..*/\1/')
        case "$CURLOCALE" in
        de_DE)
            setxkbmap -layout de
            ;;
        *)
            echo "no keyboard layout found for your locale"
            ;;
        esac
    fi

    # read cursor speed
    if iconf mousespeed; then
        echo "setting mousespeed"
        instantmouse s "$(iconf mousespeed)"
    fi

    if iconf -i reversemouse; then
        instantmouse r 1
    else
        instantmouse r 0
    fi

    if ! iconf -i noconky; then
        shuf /usr/share/instantwidgets/tooltips.txt | head -1 >~/.cache/tooltip
        conky -c /usr/share/instantwidgets/tooltips.conf &
    fi

else
    echo "live session detected"
    instantmonitor

    echo "disabling compositing for qxl graphics"
    if lshw -c video | grep -i 'qxl' || xrandr | grep -i '^qxl'; then
        iconf -i potato 1
    fi

    sudo systemctl start NetworkManager

    iconf -b welcome 1
    iconf -i wifiapplet 1
    instantwallpaper set /usr/share/instantwallpaper/defaultphoto.png
    conky -c /usr/share/instantwidgets/install.conf &
    sleep 0.3
    while :; do
        if ! pgrep python; then
            installapplet
        fi &
        sleep 6m
    done &
    sleep 1
fi

# make built in status optional
if ! iconf -i nostatus; then
    source /usr/bin/instantstatus &
fi

# compositing
if iconf -i potato || iconf -i nocompositing; then
    echo "compositing disabled"
else
    ipicom &
fi

while :; do
    lxpolkit
    sleep 10
done &

xfce4-power-manager &


# auto open menu when connecting/disconnecting monitor
if ! (iconf -i noautoswitch && iconf -i islaptop) || iconf -i autoswitch; then

    if nvidia-xconfig --query-gpu-info
    then
        DISPLAYCOUNT="$(nvidia-xconfig --query-gpu-info | grep -oi 'number of dis.*' | grep -o '[0-9]*')"
    else
        DISPLAYCOUNT="$(xrandr | grep -c '[^s]connected')"
    fi

    if [ "$DISPLAYCOUNT" -eq "$DISPLAYCOUNT" ]; then
        while :; do
            NEWDISPLAYCOUNT="$(xrandr | grep -c '[^s]connected')"
            if ! [ "$DISPLAYCOUNT" = "$NEWDISPLAYCOUNT" ]; then
                notify-send "display changed"
                echo "displays changed"
                if [ "$NEWDISPLAYCOUNT" -gt 1 ]; then
                    instantdisper
                    echo "multi monitor setup"
                else
                    disper -e
                fi
                DISPLAYCOUNT="$NEWDISPLAYCOUNT"
                # todo: open menu
            fi
            sleep 10
        done &
    else
        echo "error detecting display count"
    fi
fi

# welcome app
if iconf -b welcome; then
    instantwelcome
fi &

# prompt to fix configuration if installed from the AUR
if ! iconf -i norootinstall && ! islive; then
    if ! command -v imenu || ! command -v instantmenu; then
        notify-send "please install instantmenu and imenu"
    else
        if ! [ -e /opt/instantos/rootinstall ]; then
            imenu -m "instantOS is missing some configuration"
            while ! [ -e /tmp/rootskip ]; do
                if imenu -c "would you like to fix that?"; then
                    touch /tmp/topinstall
                    instantsudo bash -c "instantutils root"
                    touch /tmp/rootskip
                else
                    if imenu -c "Are you sure? this will prevent parts of instantOS from functioning correctly"; then
                        touch /tmp/rootskip
                    fi
                fi

            done
        fi
    fi
fi

# displays message user opens the terminal for the first time
if ! iconf -i nohelp; then
    if ! grep -q 'instantterminalhelp' ~/.zshrc; then
        echo '[[ $- == *i* ]] && instantterminalhelp' >>~/.zshrc
    fi
fi

confkey() {
    [ -n "$2" ] || return
    iconf -i "$1" || return
    xdotool key "$2"
}

# run command if iconf option is set
confcommand() {
    if iconf -i "$1"; then
        shift 1
        "$@"
    fi &
}

if iconf savebright; then
    /usr/share/instantassist/utils/b.sh 2 "$(iconf savebright)"
fi

confkey highfps "super+alt+shift+d"
confkey noanimations "super+alt+shift+s"
# disable wm alttab for graphical alttab
confkey alttab "super+alt+control+shift+Tab"

# desktop icons
confcommand desktopicons rox --pinboard Default
# auto mount disks
confcommand udiskie udiskie -t
# clipboard manager
confcommand clipmanager clipmenud

# user declared autostart
if [ -e ~/.instantautostart ]; then
    bash ~/.instantautostart
fi &

# update notifier
if ! iconf -i noupdates; then
    sleep 2m
    if checkinternet; then
        instantupdatenotify
    else
        if command -v checkinternet; then
            while :; do
                sleep 5m
                if checkinternet; then
                    instantupdatenotify
                    break
                fi
            done
        fi
    fi
fi &

# start processes that need to be kept running
while :; do
    sleep 10
    if iconf -i wifiapplet && ! pgrep nm-applet; then
        echo "starting bluetooth applet"
        nm-applet &
    fi

    if iconf -i bluetoothapplet && ! pgrep blueman-applet; then
        echo "starting bluetooth applet"
        blueman-applet &
    fi

    if iconf -i alttab && ! pgrep alttab; then
        alttab -fg "#ffffff" -bg "#292F3A" -frame "#5293E1" -d 0 -s 1 -t 128x150 -i 127x64 -w 1 -vp pointer &
    fi
    sleep 2m

done

