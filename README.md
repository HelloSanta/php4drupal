![docker hub](https://img.shields.io/docker/pulls/cobenash/php4drupal.svg?style=flat-square)
![docker hub](https://img.shields.io/docker/stars/cobenash/php4drupal.svg?style=flat-square)
![Travis](https://img.shields.io/travis/cobenash/php4drupal.svg?style=flat-square)

## 簡介
由於在開發網頁的過程當中，環境實在是太重要了。為了省很多麻煩，所以統一由Docker來統一全部的開發與正式的環境。而我主要在開發的程式Drupal，所以期望建構一個好用的影像檔，可以針對不同版本（Nginx、Apache、Php）版本進行切換環境，並且搭配Docker-compose達到非常好的使用效果。若由任何適合改進的地方，可以一起改進，讓整個系統完善。

## 適用對象
如果是在開發Drupal的網站，可以直接使用這個影像檔。我在這個影像檔裡面會加入一些Drupal需要用的設定（例如：Drush、Nginx設定）。


## 使用方法
```
docker pull hellosanta/php4drupal:latest
```
