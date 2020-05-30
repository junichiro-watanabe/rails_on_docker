#!/bin/bash

####################################################
# 以下環境をdockerで構築するためのシェルスクリプト   #
# プログラミング言語：Ruby / Ruby on rails          #
# データベース      ：mysql                         #
# webサーバ         ：Nginx                         #
####################################################


####################################################

# 開発用ユーザを指定
USER_NAME="development"
USER_PASSWORD="password"
USER="1000"
GROUP="1000"

# アプリケーションのIPアドレスを指定
APP_ADDLESS="localhost"

# 各環境のバージョンを指定
RUBY_VERSION="2.6.6"
RAILS_VERSION="6.0.2"
MYSQL_VERSION="8.0"
NGINX_VERSION="1.17.10"

####################################################


# 以下実行文
if [ $# != 1 ]; then
  echo "引数の指定が間違っています。"
  echo "ex: $0 sample"
  exit 1
fi

APP_NAME=$1
APP_DIR=`pwd`/${APP_NAME}

# 作業フォルダを作成
echo "----- Make working directories -----"
echo "mkdir -p ${APP_DIR}"
mkdir -p ${APP_DIR}
cd ${APP_DIR}
echo ""

# Dockerfile 配置用のフォルダを作成
echo "----- Make docker directories -----"
echo "mkdir -p docker/app"
mkdir -p docker/app
echo "mkdir -p docker/web"
mkdir -p docker/web
echo ""

# ソースコード配置用のフォルダを作成
echo "----- Make source directories -----"
echo "mkdir -p src/tmp/sockets"
mkdir -p src/tmp/sockets
touch src/tmp/sockets/.keep
echo ""

# DBデータ配置フォルダを作成
echo "----- Make source directories -----"
echo "mkdir -p db_data"
mkdir -p db_data
echo ""

# 各種ファイル作成
echo "----- Make source directories -----"
# app用のDockerfile 作成
echo "make app Dockerfile"
cat << EOF > docker/app/Dockerfile
FROM ruby:${RUBY_VERSION}
RUN apt-get update -y && \
    apt-get install -y default-mysql-client nodejs npm sudo && \
    npm install -g -y yarn
RUN mkdir /myapp
WORKDIR /myapp
COPY ./src/Gemfile Gemfile
COPY ./src/Gemfile.lock Gemfile.lock
RUN bundle install && \
    rails webpacker:install
RUN useradd -Nm -u ${USER} ${USER_NAME} && \
    groupadd -g ${GROUP} ${USER_NAME} && \
    usermod -aG sudo ${USER_NAME} && \
    usermod -u ${USER} -g ${GROUP} ${USER_NAME} && \
    echo ${USER_NAME}:${USER_PASSWORD} | chpasswd
COPY ./src /myapp
EOF

# web用のDockerfile 作成
echo "make web Dockerfile"
cat << EOF > docker/web/Dockerfile
FROM nginx:${NGINX_VERSION}
RUN rm -f /etc/nginx/conf.d/*
COPY ./docker/web/${APP_NAME}.conf /etc/nginx/conf.d/${APP_NAME}.conf
CMD /usr/sbin/nginx -g 'daemon off;' -c /etc/nginx/nginx.conf
EOF

# Gemfile 作成
echo "make Gemfile"
cat << EOF > src/Gemfile
source 'https://rubygems.org'
gem 'rails', '${RAILS_VERSION}'
EOF

# Gemfile.lock 作成
echo "make Gemfile"
touch ${APP_DIR}/src/Gemfile.lock

# nginx.conf 作成
echo "make ${APP_NAME}.conf"
cat << EOF > docker/web/${APP_NAME}.conf
upstream ${APP_NAME} {
  server unix:///myapp/tmp/sockets/puma.sock;
}

server {
  listen 80;
  
  server_name ${APP_ADDLESS};

  access_log /var/log/nginx/access.log;
  error_log  /var/log/nginx/error.log;

  root /myapp/public;

  client_max_body_size 100m;
  error_page 404             /404.html;
  error_page 505 502 503 504 /500.html;
  try_files  \$uri/index.html \$uri @${APP_NAME};
  keepalive_timeout 5;

  location @${APP_NAME} {
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_pass http://${APP_NAME};
  }
}
EOF

# docker-compose.yml 作成
echo "make docker-compose.yml"
cat << EOF > docker-compose.yml
version: '3'

services:
  db:
    image: mysql:${MYSQL_VERSION}
    command: --default-authentication-plugin=mysql_native_password
    environment:
      MYSQL_ROOT_PASSWORD: password
    volumes:
      - ./db_data:/var/lib/mysql
    ports:
      - 3306:3306

  app:
    build:
      context: .
      dockerfile: ./docker/app/Dockerfile
    command: bundle exec puma -C config/puma.rb
    volumes:
      - ./src:/myapp
    depends_on:
      - db

  web:
    build:
      context: .
      dockerfile: ./docker/web/Dockerfile
    volumes:
      - ./src/public:/myapp/public
      - ./src/tmp:/myapp/tmp
    ports:
      - 80:80
    depends_on:
      - app

EOF

# .circleci/config.yml 作成
echo "make .circleci/config.yml"
mkdir -p .circleci
cat << EOF > .circleci/config.yml
version: 2
jobs:
  build:
    machine:
      image: circleci/classic:edge
    working_directory: ~/repo
    steps:
      - checkout
      - run:
          name: Install Docker Compose
          command: |
            curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` > ~/docker-compose
            chmod +x ~/docker-compose
            sudo mv ~/docker-compose /usr/local/bin/docker-compose
      - run:
          name: docker-compose up --build -d
          command: docker-compose up --build -d
      - run:
          name: docker-compose run app rails db:migrate
          command: docker-compose run app rails db:migrate
      - run:
          name: docker-compose run app rails test
          command: docker-compose run app rails test
      - run:
          name: docker-compose down
          command: docker-compose down
 
workflows:
  version: 2
  workflows:
    jobs:
      - build:
          filters:
            branches:
              only: master
EOF

echo ""

# rails new 実行
echo "----- Set application -----"
echo "docker-compose run app rails new . --force --database=mysql --bundle-skip"
docker-compose run app rails new . --force --database=mysql --bundle-skip

# ファイルの権限変更
echo "sudo chown -R ${USER}:${GROUP} src docker docker-compose.yml"
sudo chown -R ${USER}:${GROUP} src docker docker-compose.yml

# database.yml を編集
echo "edit database.yml"
cat src/config/database.yml |
    sed 's/password:$/password: password/' |
    sed 's/host: localhost/host: db/' > __tmpfile__
cat __tmpfile__ > src/config/database.yml
rm __tmpfile__

# webpacker.yml を編集
echo "edit webpacker.yml"
cat src/config/webpacker.yml |
    sed 's/check_yarn_integrity: true/check_yarn_integrity: false/' > __tmpfile__
cat __tmpfile__ > src/config/webpacker.yml
rm __tmpfile__

# puba.rb を編集
echo "edit puma.rb"
cat << EOF > src/config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }.to_i
threads threads_count, threads_count
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }
plugin :tmp_restart

app_root = File.expand_path("../..", __FILE__)
bind "unix://#{app_root}/tmp/sockets/puma.sock"

stdout_redirect "#{app_root}/log/puma.stdout.log", "#{app_root}/log/puma.stderr.log", true
EOF

# .gitignore を編集
echo "edit src/.gitignore"
cat << EOF > src/.gitignore
# See https://help.github.com/articles/ignoring-files for more about ignoring files.
#
# If you find yourself ignoring temporary files generated by your text editor
# or operating system, you probably want to add a global ignore instead:
#   git config --global core.excludesfile '~/.gitignore_global'

# Ignore bundler config.
/.bundle

# Ignore all logfiles and tempfiles.
/log/*
/tmp/*
!/log/.keep
!/tmp/sockets

# Ignore uploaded files in development.
/storage/*
!/storage/.keep

/public/assets
.byebug_history

# Ignore master key for decrypting credentials and more.
/config/master.key

# Ignore unnecessary webpacker files
/public/packs
/node_modules
/yarn-error.log
yarn-debug.log*
.yarn-integrity
EOF

echo "edit db_data/.gitignore"
cat << EOF > db_data/.gitignore
/#innodb_temp
EOF

# ファイルの権限変更(2回目)
echo "sudo chown -R ${USER}:${GROUP} src docker docker-compose.yml"
sudo chown -R ${USER}:${GROUP} src docker docker-compose.yml
echo "sudo chown -R 999:999 db_data"
sudo chown -R 999:999 db_data

echo "----- container start -----"
# イメージをビルド
echo "docker-compose build"
docker-compose build

# 初回マイグレーション
echo "docker-compose run app rails db:create"
docker-compose run app rails db:create
echo "docker-compose run app rails db:migrate"
docker-compose run app rails db:migrate

# 一度コンテナをリセット
echo "docker-compose down"
docker-compose down

# コンテナ起動
echo "docker-compose up"
docker-compose up
