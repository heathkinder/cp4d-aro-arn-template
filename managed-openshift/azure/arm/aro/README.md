# README


## Scripts

All the shell scripts in the nested directory will have to be updated in accordance with the new Cloud Pak version. That is, v4.5.X. Please bear in mind all scripts, with the exception of install-pa.sh, are non functional at the time of writing as they have to be updated in accordance with the new cpd-cli.

## Pending work

1) Only PA is configured - refactor remaining services.
2) Clean up scripts to remove unneeded logic, such as JQ.
3) Conditional on whether or not the scheduler component is required. Right now, this conditional is not there present. 
4) Some input parameters are not used and can be safely removed.
5) Sudo required for the cpd-cli manage login command, but likely not required for the downstream commands.
6) Can likely get away with downsizing the bastion node from a 16s to an 8s. This speeds up deployment while cutting costs.

## Debugging tips
1) Get the process id of the script on the bastion node and tail the logs of the script by examining the correct file. For instance: sudo tail -f /proc/pid_here/fd/1 (1 and 2 for STDOUT and STDERR respectively). The cpd-cli invokes ansible scripts running on a container which have a pre-configured verbosity set. As such, there is no need for random echo statements.
2) VSCode has an extension for ARN templates, which auto checks the syntax of your template which is quite handy. More info here: https://marketplace.visualstudio.com/items?itemName=msazurermtools.azurerm-vscode-tools (Use an equivalent extension for different editors)
