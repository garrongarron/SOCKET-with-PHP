FROM php:7.4-cli
RUN docker-php-ext-install sockets
EXPOSE 9000

# docker build -t php-cli-socket .
# docker run -it --rm --name my-running-script -v ${PWD}:/usr/src/myapp -w /usr/src/myapp php-cli-socket php SalaChatServer.php
# CTRL+C to stop container
# docker stop  my-running-script
# docker rm my-running-script
# docker rmi php-cli-socket



# client

# docker run  -p 80:80 --name my-apache-php-app -v ${PWD}:/var/www/html php:7.2-apache
# docker stop  my-apache-php-app
# docker rm  my-apache-php-app