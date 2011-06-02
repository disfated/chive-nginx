# -*- mode: nginx; mode: flyspell-prog; mode: autopair; ispell-local-dictionary: "american" -*-
### Nginx configuration for Chive.

server {
    ## This is to avoid the spurious if for sub-domain name
    ## rewriting. See http://wiki.nginx.org/Pitfalls#Server_Name.
    listen [::]:80;
    server_name www.chive.example.com;
    rewrite ^ $scheme://chive.example.com$request_uri? permanent;
} # server domain rewrite.

 
server {
    listen [::]:80;
    limit_conn arbeit 10;
    server_name chive.example.com;

    ## Parameterization using hostname of access and log filenames.
    access_log  /var/log/nginx/chive.example.com_access.log;
    error_log   /var/log/nginx/chive.example.com_error.log;
    
    root /var/www/sites/chive.example.com;
    index index.php index.html;

    ## Support for favicon. Return a 204 (No Content) if the favicon
    ## doesn't exist.
    location = /favicon.ico {
        try_files /favicon.ico =204;
    }

    ## The main location is accessed using Basic Auth.
    location / {
        ## Access is restricted.
        auth_basic "Restricted Access"; # auth realm  
        auth_basic_user_file .htpasswd-users; # htpasswd file

        ## Use PATH_INFO for translating the requests to the
        ## FastCGI. This config follows Igor's suggestion here:
        ## http://forum.nginx.org/read.php?2,124378,124582.
        ## This is preferable to using:
        ## fastcgi_split_path_info ^(.+\.php)(.*)$
        ## It saves one regex in the location. Hence it's faster.
        location ~ ^(?<script>.+\.php)(?<path_info>.*)$ {
            include fastcgi.conf;
            ## The fastcgi_params must be redefined from the ones
            ## given in fastcgi.conf. No longer standard names
            ## but arbitrary: named patterns in regex.
            fastcgi_param SCRIPT_FILENAME $document_root$script;
            fastcgi_param SCRIPT_NAME $script;
            fastcgi_param PATH_INFO $path_info;
            ## Passing the request upstream to the FastCGI
            ## listener.
            fastcgi_pass phpcgi;
        }
        
        ## Protect these locations. Replicating the .htaccess
        ## rules throughout the chive distro.
        location /priv/chive/protected {
            internal;
        }
        
        location /priv/chive/yii {
            internal;
        }

        ## Static file handling.
        location ~* /priv/.+\.(?:jpg|png|css|gif|jpeg|js|swf)$ {
            expires max;
            break;
        }
    }

    # # The 404 is signaled through a static page.
    # error_page  404  /404.html;

    # ## All server error pages go to 50x.html at the document root.
    # error_page 500 502 503 504  /50x.html;
    # location = /50x.html {
    # 	root   /var/www/nginx-default;
    # }
} # server
