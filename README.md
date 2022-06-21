# PHP4Drupal

[![Build Status](https://drone.hellosanta.tw/api/badges/docker/php4drupal/status.svg?ref=refs/heads/php8.0-apache)](https://drone.hellosanta.tw/docker/php4drupal)


## 簡介
由於在開發網頁的過程當中，環境實在是太重要了。為了省很多麻煩，所以統一由Docker來統一全部的開發與正式的環境。而我主要在開發的程式Drupal，所以期望建構一個好用的映像檔，可以針對不同版本（Nginx、Apache、Php）版本進行切換環境，並且搭配Docker-compose達到非常好的使用效果。若由任何適合改進的地方，可以一起改進，讓整個系統完善

## 適用對象
如果是在開發Drupal的網站，可以直接使用這個影像檔。我在這個影像檔裡面會加入一些Drupal需要用的設定（例如：Drush、Nginx設定）。

另外，這個影像檔會需要使用者自行把網頁程式同步進去到容器內，因此並非安裝完畢之後，Drupal或其他的CMS立刻就安裝好了，這個Image比較偏向具備一些Docker知識的人使用。

## 主要功能
1. Tag來區分版本:
這個影像檔會根據Tag來區分不同的環境，主要包含Nginx+Php-FPM 跟 Apache這兩類，可以看各自的需求進行版本的切換，搭配docker-compose會有很好的效果

2. SSH支援
由於開發的需要或某一些特殊的需求，我們會需要連進入容器進行處理，因此這個影像檔有提供SSH的支援，只需要將Public key當作參數丟進來，就可以使用Private Key連到容器內。

3. 調整Apache的環境
由於每個容器可能會需要調整上傳檔案大小、記憶體、Max_input_vars等重要的變數，因此這個部分將可以直接寫在environment的變數中，直接做調整。

4. 調整Web根目錄
可以根據個人需求調整網頁的根目錄，如果沒有設定根目錄，則這裡的會預設到 /var/www/html

5. Composer支援
由於在D8上面需要composer來執行眾多的指令並且更新很多元件，因此，這裡預設安裝composer進來

6. Healthy Check支援
已經原生將Healthy Check加入影像檔之中，可以通過status看到容器的狀態

## 支援環境變數
1. SSH_KEY
2. UPLOAD_MAX_FILESIZE
3. POST_MAX_SIZE
4. MEMORY_LIMIT
5. MAX_INPUT_VARS

## Docker-Compose使用方法
如果你想要用的是docker-compose的方法來使用這個Image的話，可以參考下面的範例

```
version: "2"
services:
  web:
    image: hellosanta/php4drupal:php7.0-apache
    ports:
      - "8888:80"
      - "2338:22"   # 這個欄位可以自行決定是什麼port要對應到容器的22port
    volumes:
      - ./www:/var/www/html/
    environment:
       SSH_KEY: {這裡放你的公鑰 public key}
       UPLOAD_MAX_FILESIZE: 10
       POST_MAX_SIZE: 10
       MEMORY_LIMIT： 128
       MAX_INPUT_VARS： 1000
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

備註：如果參數太長，是可以考慮使用env_file來解決參數問題
