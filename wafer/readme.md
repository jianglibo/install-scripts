* clone wafer
* copy to /var/www/html/ and rename it.
* restart apache
* mysql -uroot -p < /var/www/html/mina_auth/db.sql
* modify system/db/db.ini
* grant all privileges on cAuth.* to 'wafer'@'127.0.0.1' identified by 'xxxxx'; flush privileges;
* use cAuth; insert into cAppinfo set appid='Your appid',secret='Your secret';
* yum install php-mysql php-mcrypt.x86_64