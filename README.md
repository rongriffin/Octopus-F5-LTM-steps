# Octopus F5 LTM steps

Octopus steps useful for blue/green deployments managed by F5's Local Traffic Manager (LTM).

##check_active_server_pool

Check if the active server pool for a specified F5 LTM virtual server is Active.  If it is, throw an error to prevent deployment to a live site.

##set_activate_server_pool

Set the server pool for a F5 LTM virtual server route traffic to a new set of servers.

##toggle_active_server_pool

Make the non-active server pool active.