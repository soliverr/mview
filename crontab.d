#
# Restart replication
#

SHELL=/bin/bash
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin
#MAILTO=


# m   h   dom   mon   dow   command

*/15  *   *     *     *     oradba-exec-sql --log-name mview_refresh 'exec mview_refresh'

# End-of-file #
