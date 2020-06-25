#!/bin/bash
#
# User-editable variables
#

# For the fileURL variable, put the complete address 
# of the zipped JamfPro QuickAdd installer package

fileURL="https://extfiles.etsy.com/corp/42epq1n5.zip"

# For the jamf_server_address variable, put the complete 
# fully qualified domain name address of your JamfPro server

jamf_server_address="scoobydoo.etsymystery.com"

# For the jamf_server_address variable, put the port number 
# of your JamfPro server. This is usually 8443; change as
# appropriate.

jamf_server_port="443"

# For the log_location variable, put the preferred 
# location of the log file for this script. If you 
# don't have a preference, using the default setting
# should be fine.

log_location="/var/log/jamfprocheck.log"

#
# The variables below this line should not need to be edited.
# Use caution if doing so. 
#

quickadd_dir="/var/root/quickadd"
quickadd_zip="$quickadd_dir/42epq1n5.zip"
quickadd_installer="$quickadd_dir/42epq1n5.pkg"
quickadd_timestamp="$quickadd_dir/quickadd_timestamp"

#
# Begin function section
# =======================
#

# Function to provide custom curl options
myCurl () { /usr/bin/curl -k -L --retry 3 --silent --show-error "$@"; }

# Function to provide logging of the script's actions to
# the log file defined by the log_location variable

ScriptLogging(){

    DATE=`date +%Y-%m-%d\ %H:%M:%S`
    LOG="$log_location"
    
    echo "$DATE" " $1" >> $LOG
}

CheckForNetwork(){

# Determine if the network is up by looking for any non-loopback network interfaces.

    local test
    
    if [[ -z "${NETWORKUP:=}" ]]; then
        test=$(ifconfig -a inet 2>/dev/null | sed -n -e '/127.0.0.1/d' -e '/0.0.0.0/d' -e '/inet/p' | wc -l)
        if [[ "${test}" -gt 0 ]]; then
            NETWORKUP="-YES-"
        else
            NETWORKUP="-NO-"
        fi
    fi
}

CheckSiteNetwork (){

  #  CheckSiteNetwork function adapted from Facebook's check_corp function script.
  #  check_corp script available on Facebook's IT-CPE Github repo:
  #
  # check_corp:
  #   This script verifies a system is on the corporate network.
  #   Input: CORP_URL= set this to a hostname on your corp network
  #   Optional ($1) contains a parameter that is used for testing.
  #   Output: Returns a check_corp variable that will return "True" if on 
  #   corp network, "False" otherwise.
  #   If a parameter is passed ($1), the check_corp variable will return it
  #   This is useful for testing scripts where you want to force check_corp
  #   to be either "True" or "False"
  # USAGE: 
  #   check_corp        # No parameter passed
  #   check_corp "True"  # Parameter of "True" is passed and returned
  

  site_network="False"
  ping=`host -W .5 $jamf_server_address`

  # If the ping fails - site_network="False"
  [[ $? -eq 0 ]] && site_network="True"

  # Check if we are using a test
  [[ -n "$1" ]] && site_network="$1"
}

#
# The update_quickadd function checks the timestamp of the fileURL variable and compares it against a locally
# cached timestamp. If the hosted file's timestamp is newer, then the JamfPro 
# QuickAdd installer gets downloaded and extracted into the target directory.
#
# This function uses the myCurl function defined at the top of the script.
#

update_quickadd () {

    # Create the destination directory if needed
    
    if [[ ! -d "$quickadd_dir" ]]; then
        mkdir "$quickadd_dir"
    fi
    
    # If needed, remove existing files from the destination directory
    
    if [[ -d "$quickadd_dir" ]]; then
        /bin/rm -rf "$quickadd_dir"/*
    fi

    # Get modification date of fileURL
    
    modDate=$(myCurl --head $fileURL 2>/dev/null | awk -F': ' '/Last-Modified/{print $2}')

    # Downloading JamfPro agent installer
    
    ScriptLogging "Downloading JamfPro agent installer from server."
    
    myCurl --output "$quickadd_zip" $fileURL
    
    # Check to make sure download occurred
    
    if [[ ! -f "$quickadd_zip" ]]; then
        ScriptLogging "$quickadd_zip not found. Exiting JamfProCheck."
        ScriptLogging "======== JamfProCheck Finished ========"
        exit 0
    fi
    
    # Verify that the downloaded zip file is a valid zip archive.

    zipfile_chk=`/usr/bin/unzip -tq $quickadd_zip > /dev/null; echo $?`

    if [ "$zipfile_chk" -eq 0 ]; then
       ScriptLogging "Downloaded zip file appears to be a valid zip archive. Proceeding."
    else
       ScriptLogging "Downloaded zip file appears to be corrupted. Exiting JamfProCheck."
       ScriptLogging "======== JamfPr0Check Finished ========"
       rm "$quickadd_zip"
       exit 0
    fi
        
    # Unzip the JamfPro agent install into the destination directory
    # and remove the __MACOSX directory, which is created as part of
    # the uncompression process from the destination directory.
    
    /usr/bin/unzip "$quickadd_zip" -d "$quickadd_dir";/bin/rm -rf "$quickadd_dir"/__MACOSX
    
    # Rename newly-downloaded installer to be jamfpro.pkg
    
    mv "$(/usr/bin/find $quickadd_dir -maxdepth 1 \( -iname \*\.pkg -o -iname \*\.mpkg \))" "$quickadd_installer"
    
    # Remove downloaded zip file
    if [[ -f "$quickadd_zip" ]]; then
        /bin/rm -rf "$quickadd_zip"
    fi
    
    # Add the quickadd_timestamp file to the destination directory. 
    # This file is used to help verify if the current JamfPro agent 
    # installer is already cached on the machine.
    
    if [[ ! -f "$quickadd_timestamp" ]]; then
        echo $modDate > "$quickadd_timestamp"
    fi   

}

CheckTomcat (){
 
# Verifies that the Jamf's Tomcat service is responding via its assigned port.


tomcat_chk=`nc -z -w 5 $jamf_server_address $jamf_server_port > /dev/null; echo $?`

if [ "$tomcat_chk" -eq 0 ]; then
       ScriptLogging "Machine can connect to $jamf_server_address over port $jamf_server_port. Proceeding."
else
       ScriptLogging "Machine cannot connect to $jamf_server_address over port $jamf_server_port. Exiting JamfProCheck."
       ScriptLogging "======== JamfProCheck Finished ========"
       exit 0
fi

}

CheckInstaller (){
 
# Compare timestamps and update the JamfPro agent 
# installer if needed.

    modDate=$(myCurl --head $fileURL 2>/dev/null | awk -F': ' '/Last-Modified/{print $2}')

if [[ -f "$quickadd_timestamp" ]]; then
    cachedDate=$(cat "$quickadd_timestamp")
    
    
    if [[ "$cachedDate" == "$modDate" ]]; then
        ScriptLogging "Current JamfPro installer already cached."
    else
        update_quickadd
    fi
else
    update_quickadd
fi

}

CheckBinary (){
 
# Identify location of jamf binary.
#
# If the jamf binary is not found, this check will return a
# null value. This null value is used by the CheckJamfPro
# function, in the "Checking for the jamf binary" section
# of the function.

jamf_binary=`/usr/bin/which jamf`

 if [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ ! -e "/usr/local/bin/jamf" ]]; then
    jamf_binary="/usr/sbin/jamf"
 elif [[ "$jamf_binary" == "" ]] && [[ ! -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
    jamf_binary="/usr/local/bin/jamf"
 elif [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
    jamf_binary="/usr/local/bin/jamf"
 fi

}

InstallJamfPro () {

 # Check for the cached JamfPro QuickAdd installer and run it
 # to fix problems with JamfPro being able to communicate with
 # the JamfPro server
 
 if [[ ! -e "$quickadd_installer" ]] ; then
    ScriptLogging "JamfPro installer is missing. Downloading."
    /bin/rm -rf "$quickadd_timestamp"
    update_quickadd
 fi
 
  if [[ -e "$quickadd_installer" ]] ; then
    ScriptLogging "JamfPro installer is present. Installing."
    /usr/sbin/installer -dumplog -verbose -pkg "$quickadd_installer" -target /
    ScriptLogging "JamfPro agent has been installed."
 fi
 

}

CheckJamfPro () {

  #  CheckJamfPro function adapted from Facebook's jamf_verify.sh script.
  #  jamf_verify script available on Facebook's IT-CPE Github repo:
  #  Link: https://github.com/facebook/IT-CPE



  # Checking for the jamf binary
  CheckBinary
  if [[ "$jamf_binary" == "" ]]; then
    ScriptLogging "JamfPro's jamf binary is missing. It needs to be reinstalled."
    InstallJamfPro
    CheckBinary
  fi

  # Verifying Permissions
  /usr/bin/chflags noschg $jamf_binary
  /usr/bin/chflags nouchg $jamf_binary
  /usr/sbin/chown root:wheel $jamf_binary
  /bin/chmod 755 $jamf_binary
  
  # Verifies that the jamf is responding to a communication query 
  # by the JamfPro agent. If the communication check returns a result
  # of anything greater than zero, the communication check has failed.
  # If the communication check fails, reinstall the JamfPro agent using
  # the cached installer.


  jamf_comm_chk=`$jamf_binary checkJSSConnection > /dev/null; echo $?`

  if [[ "$jamf_comm_chk" -eq 0 ]]; then
       ScriptLogging "Machine can connect to the jamf on $jamf_server_address."
  elif [[ "$jamf_comm_chk" -gt 0 ]]; then
       ScriptLogging "Machine cannot connect to the jamf on $jamf_server_address."
       ScriptLogging "Reinstalling JamfPro agent to fix problem of JamfPro not being able to communicate with the jamf."
       InstallJamfPro
       CheckBinary
  fi

  # Checking if machine can run a manual trigger
  # This section will need to be edited if the policy
  # being triggered has different options than the policy
  # described below:
  #
  # Trigger: isjamfup
  # Plan: Run Script isjamfonline.sh
  # 
  # The isjamfonline.sh script contains the following:
  #
  # | #!/bin/sh
  # |
  # | echo "up"
  # |
  # | exit 0
  #

  
  jamf_policy_chk=`$jamf_binary policy -trigger isjamfproup | grep "Script result: up"`

  # If the machine can run the specified policy, exit the script.

  if [[ -n "$jamf_policy_chk" ]]; then
    ScriptLogging "JamfPro enabled and able to run policies"

  # If the machine cannot run the specified policy, 
  # reinstall the JamfPro agent using the cached installer.

  elif [[ ! -n "$jamf_policy_chk" ]]; then
    ScriptLogging "Reinstalling JamfPro agent to fix problem of JamfPro not being able to run policies"
    InstallJamfPro
    CheckBinary
  fi


}

#
# End function section
# ====================
#

# The functions and variables defined above are used
# by the section below to check if the network connection
# is live, if the machine is on a network where
# the JamfPro jamf is accessible, and if the JamfPro agent on the
# machine can contact the jamf and run a policy.
#
# If the JamfPro agent on the machine cannot run a policy, the appropriate
# functions run and repair the JamfPro agent on the machine.
#

ScriptLogging "======== Starting JamfProCheck ========"

# Wait up to 60 minutes for a network connection to become 
# available which doesn't use a loopback address. This 
# condition which may occur if this script is run by a 
# LaunchDaemon at boot time.
#
# The network connection check will occur every 5 seconds
# until the 60 minute limit is reached.


ScriptLogging "Checking for active network connection."
CheckForNetwork
i=1
while [[ "${NETWORKUP}" != "-YES-" ]] && [[ $i -ne 720 ]]
do
    sleep 5
    NETWORKUP=
    CheckForNetwork
    echo $i
    i=$(( $i + 1 ))
done

# If no network connection is found within 60 minutes,
# the script will exit.

if [[ "${NETWORKUP}" != "-YES-" ]]; then
   ScriptLogging "Network connection appears to be offline. Exiting JamfProCheck."
fi
   

if [[ "${NETWORKUP}" == "-YES-" ]]; then
   ScriptLogging "Network connection appears to be live."
  
  # Sleeping for 120 seconds to give WiFi time to come online.
  ScriptLogging "Pausing for two minutes to give WiFi and DNS time to come online."
  sleep 120
  CheckSiteNetwork

  if [[ "$site_network" == "False" ]]; then
    ScriptLogging "Unable to verify access to site network. Exiting JamfProCheck."
  fi 


  if [[ "$site_network" == "True" ]]; then
    ScriptLogging "Access to site network verified"
    CheckTomcat
    CheckInstaller
    CheckJamfPro
  fi

fi

ScriptLogging "======== JamfProCheck Finished ========"

exit 0
