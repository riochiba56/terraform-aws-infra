#!/bin/bash

sudo apt update
sudo apt install -y apache2 php php-mbstring php-xml php-mysqli

wget http://ja.wordpress.org/latest-ja.tar.gz -P /tmp/
tar zxvf /tmp/latest-ja.tar.gz -C /tmp
sudo rm -rf /var/www/html/*
sudo cp -r /tmp/wordpress/* /var/www/html/
sudo chown www-data:www-data -R /var/www/html

sudo systemctl enable apache2.service
sudo systemctl restart apache2.service
