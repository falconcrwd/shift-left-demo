# Use Ubuntu as the base image
FROM ubuntu:22.04

# Update package list and install Apache web server
RUN apt-get update && \
    apt-get install -y apache2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create custom index.html page
RUN echo '<!DOCTYPE html>\
<html>\
<head>\
    <title>Falcon Cloud Security Demo</title>\
    <style>\
        body {\
            font-family: Arial, sans-serif;\
            text-align: center;\
            margin-top: 100px;\
            background-color: #f0f0f0;\
        }\
        h1 {\
            color: #333;\
            font-size: 3em;\
        }\
    </style>\
</head>\
<body>\
    <h1>Hello Falcon Cloud Security</h1>\
    <p>This is a demo web server running on Apache with Ubuntu</p>\
</body>\
</html>' > /var/www/html/index.html

# Expose port 80
EXPOSE 80

# Configure Apache to run in the foreground
RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf

# Start Apache web server
CMD ["apache2ctl", "-D", "FOREGROUND"]