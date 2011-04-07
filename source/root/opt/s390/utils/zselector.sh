#!/bin/bash
#
# QnD Hercules System version selector
# W. Kennedy
# Fri Jun  5 10:23:22 MDT 2009
#
###########################

MENU_TITLE="Please select a system"
TITLE="Hercules System Selector"


SYSOPT1="SLES9"
SYSOPT1DESC="SLES9 s/390 installer"
SYSOPT1CMD="hercules -f /opt/s390/sles9/sles9.cnf"

SYSOPT2="Debian"
SYSOPT2DESC="Debian Lenny (5.0) installer"
SYSOPT2CMD="hercules -f /opt/s390/debian/debian.cnf"

tempfile="./tempfile"

touch $tempfile

do_menu(){
dialog --title "$TITLE" \
        --menu "$MENU_TITLE:" 15 55 5 \
        "$SYSOPT1" "$SYSOPT1DESC" \
        "$SYSOPT2"  "$SYSOPT2DESC" 2> $tempfile
}

do_menu

return_value=$?

choice=`cat $tempfile`

case $return_value in
  0)
    echo "Running '$choice'..."
    case $choice in

	# If our options are recognized, run the command
        # that corresponds - set above as SYSOPTnCMD

        "$SYSOPT1")
	    sleep 2 ; xterm -e 'telnet $HOSTNAME 3270'&& x3270 $HOSTNAME 3270&
	    $SYSOPT1CMD
            exit 0
         ;;

         "$SYSOPT2")
	    $SYSOPT2CMD
            exit 0
         ;;

     esac
    ;;

  1)
    exit 0 ;;

  255)
    exit 1 ;;
# Jump back to the menu from here...
esac
