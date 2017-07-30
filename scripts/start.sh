#!/bin/bash

# 如果需要Drush的套件。
# If you need the drush components to execute on your container
if [[ "$DRUSH_USE" == "1" ]] ; then
  # php -r "readfile('https://s3.amazonaws.com/files.drush.org/drush.phar');" > drush \
  # 	  && php drush core-status \
  # 		&& chmod +x drush \
  # 		&& mv drush /usr/local/bin \
  # 		&& drush init -y
fi



# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
