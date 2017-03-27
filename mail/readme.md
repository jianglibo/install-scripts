# what's postfix
Postfix is a free and open-source mail transfer agent (MTA) that routes and delivers electronic mail, intended as an alternative to the widely used Sendmail MTA

# where does configuration file placed?
yum whatprovides */main.cf -> /etc/postfix/main.cf

# which to config
* What domain name to use in outbound mail, myorigin=$myhostname or myorigin=$mydomain
* What domains to receive mail for, mydestination = $myhostname localhost.$mydomain localhost $mydomain
* What clients to relay mail from, mynetworks = 127.0.0.0/8 168.100.189.2/32 (authorize local machine) 
* What destinations to relay mail to
* What delivery method: direct or indirect,   relayhost = (default: direct delivery to Internet), relayhost = $mydomain (deliver via local mailhub)

# test send mail
mail 391772322@qq.com

# you can start mail after starting postfix service without any change!

But you may catch "550 mail content" error!

# what's mailx
mailx is a Unix utility program for sending and receiving mail, also known as a Mail User Agent program. Being a console application with a command syntax similar to ed, it is the POSIX standardized variant[1] of the Berkeley Mail utility.[2]

# SMTP vs mail retrieval
SMTP is a delivery protocol only. In normal use, mail is "pushed" to a destination mail server (or next-hop mail server) as it arrives. Mail is routed based on the destination server, not the individual user(s) to which it is addressed. Other protocols, such as the Post Office Protocol (POP) and the Internet Message Access Protocol (IMAP) are specifically designed for use by individual users retrieving messages and managing mail boxes.

25,587,2525 or ssl: 465,25025

# Can't telnet 25 port

In main.cf, alter the line inet_interfaces = localhost.
firewall-cmd --permanent --zone=public --add-port 25/tcp

# which port to open?
Port 25 needs to be open in order for it to receive mail from the internet. All mail servers will establish a connection on port 25 and initiate TLS (encryption) on that port if necessary.

Secure SMTP (port 465) is used only by clients connecting to your server in order to send mail out.

Port 587 is considered a submission port. It is also what clients use to send mail out using your server. Port 587 is preferred in SMTP settings of clients over port 25 because port 25 is blocked by many ISPs. If you have port 465 open, you don't necessarily need port 587 open as well, but I believe 587 is considered a standard and 465 is considered legacy.

Port 25 should accept anonymous connections, but not for relaying

Ports 465 and 587 should reject anonymous connections and allow relaying.

Don't apologize for not knowing. We all start somewhere, and nobody on here knows everything :-)