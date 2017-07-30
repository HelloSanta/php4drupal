#!/bin/bash


## 備註：這個舉動可以讓一半user通過Key就可以直接連線到容器裡面，目前是為了方便起見這樣處理，未來也許會加入個條件來讓使用者決定
## 是否要這樣的功能，照理說 Production的網站是不太需要的
## settings SSH

if [ ! -z "$SSH_KEY" ]; then
  echo 'root:root' |  #將root帳號，密碼設定為root
  #sed [-OPTION] [ADD1][,ADD2] [COMMAND] [/PATTERN][/REPLACEMENT]/[FLAG] [FILE]
  #s/樣板(PATTERN)/取代(REPLACEMENT)/
  sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config # -i :代表插入一行字
  # 這個設定就是讓密碼登入無效
  echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  mkdir /var/run/sshd && chmod 0755 /var/run/sshd
  mkdir -p /root/.ssh/
  # 將 etc/pam.d/sshd 裡面設定為session optional pam_loginuid.so，為了支援可以使用ssh連到container
  sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi


# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
