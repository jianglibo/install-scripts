mysql-community-server	Database server and related tools
mysql-community-client	MySQL client applications and tools
mysql-community-common	Common files for server and client libraries
mysql-community-devel	Development header files and libraries for MySQL database client applications
mysql-community-libs	Shared libraries for MySQL database client applications
mysql-community-libs-compat	Shared compatibility libraries for previous MySQL installations
mysql-community-embedded	MySQL embedded library
mysql-community-embedded-devel	Development header files and libraries for MySQL as an embeddable library
mysql-community-test	Test suite for the MySQL server

Client programs and scripts	/usr/bin
mysqld server	/usr/sbin
Configuration file	/etc/my.cnf
Data directory	/var/lib/mysql
Error log file
For RHEL, Oracle Linux, CentOS or Fedora platforms: /var/log/mysqld.log

For SLES: /var/log/mysql/mysqld.log

Value of secure_file_priv	/var/lib/mysql-files
System V init script
For RHEL, Oracle Linux, CentOS or Fedora platforms: /etc/init.d/mysqld

For SLES: /etc/init.d/mysql

Systemd service
For RHEL, Oracle Linux, CentOS or Fedora platforms: mysqld

For SLES: mysql

Pid file	/var/run/mysql/mysqld.pid
Socket	/var/lib/mysql/mysql.sock
Keyring directory	/var/lib/mysql-keyring
Unix manual pages	/usr/share/man
Include (header) files	/usr/include/mysql
Libraries	/usr/lib/mysql
Miscellaneous support files (for example, error messages, and character set files)	/usr/share/mysql


yum install mysql-community-{server,client,common,libs}-*
http://dev.mysql.com/doc/refman/5.7/en/postinstallation.html

mkdir mysql-files
chmod 750 mysql-files

Any long option that may be given on the command line when running a MySQL program can be given in an option file as well. To get the list of available options for a program, run it with the --help option. (For mysqld, use --verbose and --help.)
