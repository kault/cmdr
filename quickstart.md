#Quickstart
cmdr is a low-cost solution to control devices typically found in
multimedia classrooms. The main project can be found [here](https://github.com/wesleyan/cmdr).

##The Bits and Pieces
###The Deployment Process
cmdr itself is just a bit of software responsible for handling messages between devices.
Nonetheless, a fair amount of setup is required before things can get working.
Our current model consists of:
* Asus EeeBox PC EB1030
* Mimo Touch 2 Display USB Touchscreen
* Ubuntu Server

We use a custom build of Ubuntu Server LTS that does most of the preconfiguration
for us. Information on how to create the image can be found
[here](https://github.com/wesleyan/cmdr/wiki/Preparing-the-cmdr-OS).
The isolinux.cfg file is responsible for booting into the installer
without the need of any user input whereas the preseed file is
responsible for setting up a default user and environment
as well as running our postinstall.sh script which configures chef.
Instructions on how to deploy the cmdr software can be found
[here](https://github.com/wesleyan/cmdr/wiki/Deploying-a-new-cmdr-controller).

###Dependencies
Dependencies have to be manually installed.
* CouchDB >= 1.2
* [RVM](https://rvm.io/)
* Ruby 1.9.3 (Install with RVM)
* RabbitMQ-Server
* Avahi-Daemon (optional dependency for cmdr-server integration)

###cmdr
cmdr consists primarily of three parts. 
1. [cmdr-daemon](https://github.com/wesleyan/cmdr): This is the main 
    program that controls the devices.
2. [cmdr-devices](https://github.com/wesleyan/cmdr-devices): The drivers
    that handle communication between the devices and cmdr.
3. [cmdr-server](https://github.com/wesleyan/cmdr-server): Though not a
    critical component of cmdr, cmdr-server offers a one-stop solution
    for users to configure and monitor multiple cmdr instances.
