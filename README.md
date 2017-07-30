[![GitHub issues](https://img.shields.io/github/issues/cobenash/php4drupal.svg?style=plastic)](https://github.com/cobenash/php4drupal/issues)
[![GitHub forks](https://img.shields.io/github/forks/cobenash/php4drupal.svg?style=plastic)](https://github.com/cobenash/php4drupal/network)
[![GitHub stars](https://img.shields.io/github/stars/cobenash/php4drupal.svg?style=plastic)](https://github.com/cobenash/php4drupal/stargazers)

## 簡介
由於在開發網頁的過程當中，環境實在是太重要了。為了省很多麻煩，所以統一由Docker來統一全部的開發與正式的環境。而我主要在開發的程式Drupal，所以期望建構一個好用的影像檔，可以針對不同版本（Nginx、Apache、Php）版本進行切換環境，並且搭配Docker-compose達到非常好的使用效果。若由任何適合改進的地方，可以一起改進，讓整個系統完善

## 適用對象
如果是在開發Drupal的網站，可以直接使用這個影像檔。我在這個影像檔裡面會加入一些Drupal需要用的設定（例如：Drush、Nginx設定）。


## 主要功能
1. Tag來區分版本:  
這個影像檔會根據Tag來區分不同的環境，主要包含Nginx+Php-FPM 跟 Apache這兩類，可以看各自的需求進行版本的切換，搭配docker-compose會有很好的效果

2. SSH支援  
由於開發的需要或某一些特殊的需求，我們會需要連進入容器進行處理，因此這個影像檔有提供SSH的支援，只需要將Public key當作參數丟進來，就可以使用Private Key連到容器內。

## 使用方法
使用方法很多，建議使用docker-compose，可以一次把該設定的設定完畢

```
version: "2"  
services:  
  web:
    image: php4drupal:test
    ports:
      - "8888:80"
      - "2338:22"   # 這個欄位可以自行決定是什麼port要對應到容器的22port
    volumes:
      - ./www:/var/www/html/
    environment:
       SSH_KEY: {這裡放你的公鑰 public key}
    restart: always
    links:
      - db
  db:
    image: mysql:5.7.18
    volumes:
      - ./mysql/db:/var/lib/mysql
    environment:
      - MYSQL_USER=drupal
      - MYSQL_PASSWORD=drupal
      - MYSQL_DATABASE=drupal
      - MYSQL_ROOT_PASSWORD=drupal
```
