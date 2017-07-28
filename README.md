## 前言
這個版本的Dockerfile，主要是拿來建構Drupal的環境，主要是PHP+Nginx的組合，不同的Tag則代表者不同的php版本或者安裝了不同的php插件。用了這個Dockerfile，將可以做到各個網頁環境的一致性。

## 安裝項目
在這個repo裡面，包含的項目包含了以下的套件,而版本將會是最新的版本

1. Nginx
2. php-fpm
3. Mysql
4. Drush

## 適用範圍
這個會把開發用的Key加入到影像檔裡面。以方便使用Drush+Features的開發流程，因此，**請勿**使用在開發的環境中。
