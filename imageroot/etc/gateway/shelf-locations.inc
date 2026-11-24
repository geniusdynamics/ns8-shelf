# No access log: request URLs of Supabase Storage carry signed tokens
access_log off;

client_max_body_size 100m;

proxy_http_version 1.1;
proxy_set_header Host $http_host;
# Traefik is the only trusted proxy: pass on what it sets
proxy_set_header X-Forwarded-For $http_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_read_timeout 300s;
proxy_send_timeout 300s;

# Supabase Auth (GoTrue): the path prefix is stripped, like Supabase's own gateway does
location /auth/v1/ {
    proxy_pass http://127.0.0.1:9999/;
}

# Supabase Storage: the path prefix is stripped
location /storage/v1/ {
    proxy_pass http://127.0.0.1:5000/;
}

# Shelf
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_buffering off;
}
