#JamfProCheck previously known as CasperCheck

For folks using [JAMF Software's JamfPro](https://www.jamf.com/) solution, sometimes the JamfPro agent installed on individual Macs stops working properly. They stop checking in with the JamfPro server, or check in but can't run policies anymore. To help address this issue, JamfProCheck provides an automated way to check and repair JamfPro agents that are not working properly. As designed, this solution will do the following:

A. Check to see if a JamfPro-managed Mac's network connection is live<br/>
B. If the network is working, check to see if the machine is on a network where the Mac's Casper JamfPro Server is accessible.<br/>
C. If both of the conditions above are true, check to see if the JamfPro agent on the machine can contact the JamfPro Server and run a policy.<br/>
D. If the JamfPro agent on the machine cannot run a policy, the appropriate functions run and repair the JamfPro agent on the machine.<br/>

As written currently, JamfProCheck has several components that work together:

1. A JamfPro policy that runs when called by a manual trigger.

2. A zipped JamfPro QuickAdd installer package, available for download from a web server.

3. A LaunchDaemon, which triggers the JamfProCheck script to run

4. The JamfPro script


Here's how the various parts are set up:


## JamfPro policy

The JamfPro policy check which is written into the script needs to be set up as follows:

**Name:** JamfPro Online<br/>
**Scope:** All Computers<br/>
**Trigger:** Manual triggered by "isjamfproup" (no quotes)<br/>
**Frequency:** Ongoing<br/>
**Plan:** Run Script isJamfProonline.sh<br/>

```sh
#!/bin/sh
echo "up"
exit 0
```

When run, the policy will return `Script result: up` among other output. The JamfProCheck script verifies if it's received the `Script result: up` output and will use that as the indicator that policies can be successfully run by the JamfPro agent.


## Zipped QuickAdd installer posted to web server

For the QuickAdd installer, I generated a QuickAdd installer using JamfPro Recon. This is because QuickAdds made by Recon include an unlimited enrollment invitation, which means that the same package can be used to enroll multiple machines with the JamfPro Server in question. Once the QuickAdd package was created by Recon, I then used OS X's built-in compression app to generate a zip archive of the QuickAdd installer. The zipped QuickAdd can be posted to any web server.


## LaunchDaemon

As currently written, JamfProCheck is set to run on startup and then once every week. To facilitate this, it's using a LaunchDaemon similar to the one below.

The LaunchDaemon will run on the following command on startup. After startup, the script will then run every day at 12pm: `sh /Library/Scripts/jamfprocheck.sh`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.company.jamfprocheck</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/Library/Scripts/jamfprocheck.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>12</integer>
		<key>Minute</key>
		<integer>00</integer>
	</dict>
</dict>
</plist>
```


## JamfProCheck script

The current version of the CasperCheck script is available from the following location:
This repo's script folder JamfProCheck/script/jamfprocheck.sh

Originally
[CasperCheck](https://github.com/rtrouton/CasperCheck/blob/master/script/caspercheck.sh)


The JamfProCheck script includes functions to do the following:

1. Check to verify that the Mac has a network connection that does not use a loopback address (like 127.0.0.1 or 0.0.0.0)

2. Verify that it can resolve the JamfPro Server's server address and that the appropriate network port is accepting connections.

3. As needed, download and store new QuickAdd installers from the web server where the zipped QuickAdds are posted to.

4. Check to see if the JamfPro binary is present. If not, reinstall using the QuickAdd installer stored on the Mac.

5. If the JamfPro binary is present, verify that it has the proper permissions and automatically fix any permissions that are incorrect.

6. Check to see if the Mac can communicate with the JamfPro server using the "jamf checkJSSConnection" command. If not, reinstall using the QuickAdd installer stored on the Mac.

7. Check to see if the Mac can run a specified policy using a manual trigger. If not, reinstall using the QuickAdd installer stored on the Mac.

Assuming that the JamfPro Online policy has been set up described above on the JamfPro Server, the variables below need to be set up on the JamfProCheck script to set the following variables before using it in your environment:

*fileURL* - For the fileURL variable, put the complete address of the zipped Casper QuickAdd installer package.
*jamfpro_server_address* - put the complete fully qualified domain name address of your Casper server.
*jamfpro_server_port* - put the appropriate port number for your Casper server. This is usually 8443 or 443; change as appropriate.
*log_location* - put the preferred location of the log file for this script. If you don't have a preference, using the default setting of /var/log/jamfprocheck.log should be fine.<br/>
**NOTE:** Use caution when editing the functions or variables below the User-editable variables section of the script.


## JamfProCheck in operation

There's a number of checks built into the JamfProCheck script. Here's how the script works in operation:

1. The script will run a check to see if it has a network address that is not a loopback address (like 127.0.0.1 or 0.0.0.0). If needed, the script will wait up to 60 minutes for a network connection to become available which doesn't use a loopback address.

   **Note:** The network connection check will occur every 5 seconds until the 60 minute limit is reached. If no network connection is found within 60 minutes, the script will exit at that point.

2. Once a network connection is established that passes the initial connection check, the script then pauses for two minutes to allow WiFi connections and DNS to come online and begin working.

3. A check is then run to ensure that the Mac is on the correct network by verifying that it can resolve the fully qualified domain name of the JamfPro server. If the verification check fails, the script will exit at that point.

4. Once the "correct network" check is passed, a check is then run to verify that the JamfPro Server's Tomcat service is responding via its port number.

5. Once the Tomcat service check is passed, a check is then run to verify that the latest available QuickAdd installer has been downloaded to the Mac. If not, a new QuickAdd installer is downloaded as a .zip file from the web server which hosts the zipped QuickAdd.

   Once downloaded, the zip file is then checked to see if it is a valid zip archive. If the zip file check fails, the script will exit at that point.

   If all of the above checks described above are passed, the JamfProCheck script has verified the following:

   A. It's got a network connection<br/>
   B. It can actually see the JamfPro server<br/>
   C. The Tomcat web service used by the JamfProServer for communication between the server and the JamfPro agent on the Mac is up and running.<br/>
   D. The current version of the QuickAdd installer is stored on the Mac<br/>

   At this point, the script will proceed with verifying whether the JamfPro agent on the Mac is working properly.

6. A check is run to ensure that the JAMF binary used by the JamfPro agent is present. If not, the JamfProCheck script will reinstall the JamfPro agent using the QuickAdd installer stored on the Mac.

7. If the JAMF binary is present, the JamfProCheck script runs commands to verify that it has the proper permissions and automatically fix any permissions that are incorrect.

8. A check is run using the `jamf checkJSSConnection` command to make sure that the JamfPro agent can communicate with the JamfPro Server service. This check should usually succeed, but may fail in the following circumstances:

   A. The JamfPro agent on the machine was originally talking to the JamfPro Server at a different DNS address - In the event that the JamfPro server has moved to a different DNS address from the one that the JamfPro agent is expecting, this check will fail.<br/>
   B. The JamfPro agent is present but so broken that it cannot contact the JamfPro Server service using the checkJSSConnection function.<br/>

   If the check fails, the JamfProCheck script will reinstall the JamfPro agent using the QuickAdd installer stored on the Mac.

9. The final check verifies if the Mac can run the specified policy. If the check fails, the JamfProcheck script will reinstall the JamfPro agent using the QuickAdd installer stored on the Mac.

Note: If you run `which jamf` with Casper 9.8 and later on Macs running 10.7 and later, you'll get back a result of `/usr/local/bin/jamf` as being the path to the JamfPro agent's `jamf` binary. While the actual `jamf` binary is located elsewhere in the filesystem, JamfProCheck will be checking for the presence of the `/usr/local/bin/jamf` symlink.

If the symlink is missing, JamfProCheck's interpretation is that the symlink's absence means the JamfPro agent is not working properly and needs to be reinstalled using the QuickAdd installer stored on the Mac.


Blog Posts
-----------

https://derflounder.wordpress.com/category/caspercheck/

