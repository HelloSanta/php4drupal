#!/bin/bash


## 備註 如果有設定SSH key，就會自動啟動服務，並且把key寫入，讓外部可以通過ip跟port連到container裡面
## settings SSH
if [ ! -z "$SSH_KEY" ]; then
  echo 'root:root' | chpasswd #將root帳號，密碼設定為root
  #sed [-OPTION] [ADD1][,ADD2] [COMMAND] [/PATTERN][/REPLACEMENT]/[FLAG] [FILE]
  #s/樣板(PATTERN)/取代(REPLACEMENT)/
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config # -i :代表插入一行字
  # 這個設定就是讓密碼登入無效
  echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config

  mkdir /var/run/sshd && chmod 0755 /var/run/sshd
  mkdir -p /root/.ssh/
  # 將 etc/pam.d/sshd 裡面設定為session optional pam_loginuid.so，為了支援可以使用ssh連到container
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
  echo "$SSH_KEY" > /root/.ssh/authorized_keys
fi

if [ ! -z "$UPLOAD_MAX_FILESIZE" ];then
  sed -i "s@upload_max_filesize = 10M@upload_max_filesize = ${UPLOAD_MAX_FILESIZE}M@g" /usr/local/etc/php/php.ini
fi

if [ ! -z "$POST_MAX_SIZE" ];then
  sed -i "s@post_max_size = 10M@post_max_size = ${POST_MAX_SIZE}M@g" /usr/local/etc/php/php.ini
fi

if [ ! -z "$MEMORY_LIMIT" ];then
  sed -i "s@memory_limit = 128M@memory_limit = ${MEMORY_LIMIT}M@g" /usr/local/etc/php/php.ini
fi

if [ ! -z "$MAX_INPUT_VARS" ];then
  sed -i "s@max_input_vars = 2000@max_input_vars = ${MAX_INPUT_VARS}@g" /usr/local/etc/php/php.ini
fi

if [ ! -z "$WEB_ROOT" ];then
  sed -i "s@DocumentRoot /var/www/html@DocumentRoot ${WEB_ROOT}@g" /etc/apache2/sites-available/000-default.conf
  sed -i "s@Directory /var/www/html@Directory ${WEB_ROOT}@g" /etc/apache2/apache2.conf
fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
