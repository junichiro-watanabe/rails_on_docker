#!/bin/bash

####################################################
# 以下環境をdockerで構築するためのシェルスクリプト   #
# プログラミング言語：Ruby / Ruby on rails          #
# データベース      ：mysql                         #
# webサーバ         ：Nginx                         #
####################################################


####################################################

# 各環境のバージョンを指定
RUBY_VERSION="2.6.6"
RAILS_VERSION="6.0.2"
MYSQL_VERSION="8.0"
NGINX_VERSION="1.17.10"

# アプリケーションのIPアドレスを指定
APP_ADDLESS="app"

# 開発DB環境設定
MYSQL_ROOT_PASSWORD="5la&2Rj%4"

# 本番DB環境設定
MYSQL_HOST_PRODUCTION="ecstest-db.cn8ls5rgklmn.ap-northeast-1.rds.amazonaws.com"

# 開発用ユーザを指定
USER_NAME="development"
USER_PASSWORD="password"
USER="1000"
GROUP="1000"

# CircleCI上で指定が必要な環境変数
# AWS_ACCOUNT_ID          : AWSのデフォルトリージョン
# AWS_ACCESS_KEY_ID       : AWSのアクセスキー
# AWS_SECRET_ACCESS_KEY   : AWSのシークレットキー
# AWS_REGION              : AWSのデフォルトリージョン
# AWS_ECR_ACCOUNT_URL     : AWS ECRリポジトリのURL

# AWS上で指定が必要な環境変数
# RAILS_MASTER_KEY          : ローカル環境にあるmaster.keyの値
# MYAPP_DATABASE_USER       : 本番環境データベースユーザ
# MYAPP_DATABASE_PASSWORD   : 本番環境データベースパスワード

####################################################


# 以下実行文
if [ $# != 1 ]; then
  echo "引数の指定が間違っています。"
  echo "ex: $0 myapp"
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

# 各種ファイル作成
echo "----- Make source directories -----"
# app用のDockerfile 作成(開発用)
echo "make app Dockerfile"
cat << EOF > docker/app/Dockerfile_development
FROM ruby:${RUBY_VERSION}
RUN apt-get update -y && \\
    apt-get install -y default-mysql-client nodejs npm sudo && \\
    npm install -g -y yarn
RUN mkdir /${APP_NAME}
WORKDIR /${APP_NAME}
COPY ./src/Gemfile Gemfile
COPY ./src/Gemfile.lock Gemfile.lock
RUN bundle install && \\
    rails webpacker:install
RUN useradd -Nm -u ${USER} ${USER_NAME} && \\
    groupadd -g ${GROUP} ${USER_NAME} && \\
    usermod -aG sudo ${USER_NAME} && \\
    usermod -u ${USER} -g ${GROUP} ${USER_NAME} && \\
    echo ${USER_NAME}:${USER_PASSWORD} | chpasswd
COPY ./src /${APP_NAME}
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
EOF

# app用のDockerfile 作成(本番用)
cat << EOF > docker/app/Dockerfile_production
FROM ruby:${RUBY_VERSION}
RUN apt-get update -y && \\
    apt-get install -y default-mysql-client nodejs npm sudo && \\
    npm install -g -y yarn
RUN mkdir /${APP_NAME}
WORKDIR /${APP_NAME}
COPY ./src/Gemfile Gemfile
COPY ./src/Gemfile.lock Gemfile.lock
RUN bundle install && \\
    rails webpacker:install
COPY ./src /${APP_NAME}
CMD ["bundle", "exec", "puma", "-e", "production", "-C", "config/puma.rb"]
EOF

# web用のDockerfile 作成
echo "make web Dockerfile"
cat << EOF > docker/web/Dockerfile
FROM nginx:${NGINX_VERSION}
RUN rm -f /etc/nginx/conf.d/*
COPY ./docker/web/${APP_NAME}.conf /etc/nginx/conf.d/${APP_NAME}.conf
CMD ["/usr/sbin/nginx", "-g", "daemon off;", "-c", "/etc/nginx/nginx.conf"]
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
  server ${APP_ADDLESS}:3000;
}

server {
  listen 80;
  
  server_name ${APP_ADDLESS};

  access_log /var/log/nginx/access.log;
  error_log  /var/log/nginx/error.log;

  root /${APP_NAME}/public;

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
volumes:
  db_data:

services:
  db:
    image: mysql:${MYSQL_VERSION}
    command: --default-authentication-plugin=mysql_native_password
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - 3306

  app:
    build:
      context: .
      dockerfile: ./docker/app/Dockerfile_development
    volumes:
      - ./src:/${APP_NAME}
    ports:
      - 3000
    depends_on:
      - db

  web:
    build:
      context: .
      dockerfile: ./docker/web/Dockerfile
    volumes:
      - ./src/public:/${APP_NAME}/public
      - ./src/tmp:/${APP_NAME}/tmp
    ports:
      - 80:80
    depends_on:
      - app

EOF

# .circleci/config.yml 作成
echo "make .circleci/config.yml"
mkdir -p .circleci
cat << EOF > .circleci/config.yml
version: 2.1
jobs:
  test:
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
      - run: sleep 30
      - run:
          name: docker-compose run app rails db:create
          command: docker-compose run app rails db:create
      - run:
          name: docker-compose run app rails db:migrate
          command: docker-compose run app rails db:migrate
      - run:
          name: docker-compose run app bundle exec rspec spec
          command: docker-compose run app bundle exec rspec spec
      - run:
          name: docker-compose down
          command: docker-compose down

orbs:
  aws-ecr: circleci/aws-ecr@6.0.0
  aws-ecs: circleci/aws-ecs@0.0.8

workflows:
  test:
    jobs:
      - test
  deploy-web:
    jobs:
      - aws-ecr/build-and-push-image:
          filters:
            branches:
              only: master
          account-url: AWS_ECR_ACCOUNT_URL
          create-repo: true
          dockerfile: docker/web/Dockerfile
          repo: "${APP_NAME}_web"
          region: AWS_REGION
          tag: "\${CIRCLE_SHA1}"
      - aws-ecs/deploy-service-update:
          requires:
            - aws-ecr/build-and-push-image
          family: "${APP_NAME}-task"
          cluster-name: "${APP_NAME}-cluster"
          service-name: "${APP_NAME}-service"
          container-image-name-updates: "container=web,tag=\${CIRCLE_SHA1}"
  deploy-app:
    jobs:
      - aws-ecr/build-and-push-image:
          filters:
            branches:
              only: master
          account-url: AWS_ECR_ACCOUNT_URL
          create-repo: true
          dockerfile: docker/app/Dockerfile_production
          repo: "${APP_NAME}_app"
          region: AWS_REGION
          tag: "\${CIRCLE_SHA1}"
      - aws-ecs/deploy-service-update:
          requires:
            - aws-ecr/build-and-push-image
          family: "${APP_NAME}-task"
          cluster-name: "${APP_NAME}-cluster"
          service-name: "${APP_NAME}-service"
          container-image-name-updates: "container=app,tag=\${CIRCLE_SHA1}"
EOF

echo ""

# rails new 実行
echo "----- Set application -----"
echo "docker-compose run app rails new . --force --database=mysql --bundle-skip"
docker-compose run app rails new . --force --database=mysql --bundle-skip

# ファイルの権限変更
echo "sudo chown -R ${USER}:${GROUP} ."
sudo chown -R ${USER}:${GROUP} .

# Gemfile を編集
echo "edit Gemfile"
cat << EOF > src/Gemfile
source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.6.6'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.0.2'
# Use mysql as the database for Active Record
gem 'mysql2', '>= 0.4.4'
# Use Puma as the app server
gem 'puma', '~> 4.1'
# Use SCSS for stylesheets
gem 'sass-rails', '>= 6'
# Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker
gem 'webpacker', '~> 4.0'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.4.2', require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
EOF

# database.yml を編集
echo "edit database.yml"
cat << EOF > src/config/database.yml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: ${MYSQL_ROOT_PASSWORD}
  host: db

development:
  <<: *default
  database: ${APP_NAME}_development

test:
  <<: *default
  database: ${APP_NAME}_test

production:
  <<: *default
  database: ${APP_NAME}_production
  username: <%= ENV['MYAPP_DATABASE_USER'] %>
  password: <%= ENV['MYAPP_DATABASE_PASSWORD'] %>
  host: ${MYSQL_HOST_PRODUCTION}
EOF

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

/public/assets/*.br
/public/assets/*.gz
.byebug_history

# Ignore master key for decrypting credentials and more.
/config/master.key

# Ignore unnecessary webpacker files
/public/packs/*.br
/public/packs/*.gz
/public/packs/js/*.br
/public/packs/js/*.gz
/public/packs-test/*.br
/public/packs-test/*.gz
/public/packs-test/js/*.br
/public/packs-test/js/*.gz
/node_modules
/yarn-error.log
yarn-debug.log*
.yarn-integrity
EOF

# ファイルの権限変更(2回目)
echo "sudo chown -R ${USER}:${GROUP} ."
sudo chown -R ${USER}:${GROUP} .

echo "----- container start -----"
# イメージをビルド
echo "docker-compose build"
docker-compose build

# 初回マイグレーション
echo "docker-compose run app bundle exec rails generate rspec:install"
docker-compose run app bundle exec rails generate rspec:install
echo "docker-compose run app rails db:create"
docker-compose run app rails db:create
echo "docker-compose run app rails db:migrate"
docker-compose run app rails db:migrate

# 本番用プリコンパイル
echo "rails assets:precompile RAILS_ENV=production"
docker-compose run app rails assets:precompile RAILS_ENV=production

# ファイルの権限変更(2回目)
echo "sudo chown -R ${USER}:${GROUP} ."
sudo chown -R ${USER}:${GROUP} .

# 一度コンテナをリセット
echo "docker-compose down"
docker-compose down

# コンテナ起動
echo "docker-compose up"
docker-compose up
