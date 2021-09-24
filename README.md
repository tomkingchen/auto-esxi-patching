# auto-esxi-patching
PowerShell scripts to automate VMware ESXi hosts patching

Assume you have:
- vSphere version 6.5 or later
- PRTG for monitoring
- PowerCLI module
- PrtgAPI module

The main script does the following
1. Ask for priviledged account credential.
2. Pause PRTG sensors before patching.
3. Prompt for acknowledge to kick off patching.
4. Move VMs off the host.
5. Update the host.
6. Move VMs back onto the patched host.
7. Move onto next host.
8. Resume sensors after successful patching.
