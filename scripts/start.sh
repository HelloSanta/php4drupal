#!/bin/bash

# 如果需要Drush的套件。
# If you need the drush components to execute on your container
#if [[ "$DRUSH_USE" == "1" ]] ; then
#  
#fi



# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
