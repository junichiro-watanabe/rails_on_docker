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

# アプリケーションのIPアドレスを指定
APP_DOMAIN=".watanavi.work"

# 開発DB環境設定
MYSQL_ROOT_PASSWORD="5la&2Rj%4"

# 本番DB環境設定
MYSQL_HOST_PRODUCTION="ecstest-db.cn8ls5rgklmn.ap-northeast-1.rds.amazonaws.com"

# S3バケット設定
AWS_BUCKET = "habitapp"
AWS_REGION = "ap-northeast-1"

# 開発用ユーザを指定
USER_NAME="dev"
USER_PASSWORD="password"
USER="1000"
GROUP="1000"

# ローカル環境で必要な設定
# EDITOR=vi rails credentials:edit
# aws:
#  access_key_id: アクセスキー
#  secret_access_key: シークレットキー

# CircleCI上で指定が必要な環境変数
# AWS_ACCOUNT_ID          : AWSアカウント
# AWS_ACCESS_KEY_ID       : AWSのアクセスキー
# AWS_SECRET_ACCESS_KEY   : AWSのシークレットキー
# AWS_REGION              : AWSのデフォルトリージョン
# AWS_ECR_ACCOUNT_URL     : AWS ECRリポジトリのURL

# AWS上で指定が必要な環境変数
# RAILS_MASTER_KEY          : ローカル環境にあるmaster.keyの値
# MYAPP_DATABASE_USER       : 本番環境データベースユーザ
# MYAPP_DATABASE_PASSWORD   : 本番環境データベースパスワード
# webコンテナのネットワーク設置：linkを「app:app」に設定

####################################################

# 以下実行文
if [ $# != 1 ]; then
  echo "引数の指定が間違っています。"
  echo "ex: $0 myapp"
  exit 1
fi

APP_NAME=$1
APP_DIR=$(pwd)/${APP_NAME}

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
cat <<EOF >docker/app/Dockerfile_development
FROM ruby:${RUBY_VERSION}
RUN apt-get update -y && \\
  apt-get install --no-install-recommends -y \\
  default-mysql-client \\
  nodejs \\
  npm \\
  sudo && \\
  npm install -g -y yarn && \\
  apt-get clean && \\
  rm -rf /var/lib/apt/lists/*
RUN mkdir /${APP_NAME}
WORKDIR /${APP_NAME}
COPY ./src/Gemfile Gemfile
COPY ./src/Gemfile.lock Gemfile.lock
RUN bundle install && \\
    bundle exec rails webpacker:install
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN useradd -Nm -u ${USER} ${USER_NAME} && \\
  groupadd -g ${GROUP} ${USER_NAME} && \\
  usermod -aG sudo ${USER_NAME} && \\
  usermod -u ${USER} -g ${GROUP} ${USER_NAME} && \\
  echo ${USER_NAME}:${USER_PASSWORD} | chpasswd
RUN cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \\
    echo "Asia/Tokyo" > /etc/timezone
COPY ./src /${APP_NAME}
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
EOF

# app用のDockerfile 作成(本番用)
cat <<EOF >docker/app/Dockerfile_production
FROM ruby:${RUBY_VERSION}
RUN apt-get update -y && \\
  apt-get install --no-install-recommends -y \\
  default-mysql-client \\
  nodejs \\
  npm \\
  sudo && \\
  npm install -g -y yarn && \\
  apt-get clean && \\
  rm -rf /var/lib/apt/lists/*
RUN mkdir /${APP_NAME}
WORKDIR /${APP_NAME}
COPY ./src/Gemfile Gemfile
COPY ./src/Gemfile.lock Gemfile.lock
RUN bundle install && \\
    bundle exec rails webpacker:install
RUN cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \\
    echo "Asia/Tokyo" > /etc/timezone
COPY ./src /${APP_NAME}
RUN SECRET_KEY_BASE=tempvalue rails assets:precompile RAILS_ENV=production && \\
    yarn cache clean && \\
    rm -rf node_modules tmp/cache
ENV RAILS_SERVE_STATIC_FILES="true"
CMD ["bundle", "exec", "puma", "-e", "production", "-C", "config/puma.rb"]
EOF

# web用のDockerfile 作成
echo "make web Dockerfile"
cat <<EOF >docker/web/Dockerfile
FROM nginx:${NGINX_VERSION}
RUN rm -f /etc/nginx/conf.d/*
COPY ./docker/web/${APP_NAME}.conf /etc/nginx/conf.d/${APP_NAME}.conf
CMD ["/usr/sbin/nginx", "-g", "daemon off;", "-c", "/etc/nginx/nginx.conf"]
EOF

# Gemfile 作成
echo "make Gemfile"
cat <<EOF >src/Gemfile
source 'https://rubygems.org'
gem 'rails', '${RAILS_VERSION}'
EOF

# Gemfile.lock 作成
echo "make Gemfile"
touch ${APP_DIR}/src/Gemfile.lock

# nginx.conf 作成
echo "make ${APP_NAME}.conf"
cat <<EOF >docker/web/${APP_NAME}.conf
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
cat <<EOF >docker-compose.yml
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
    environment:
      - "SELENIUM_DRIVER_URL=http://chrome:4444/wd/hub"

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

  chrome:
    image: selenium/standalone-chrome-debug:latest
    logging:
      driver: none
    ports:
      - 4444:4444

EOF

# .circleci/config.yml 作成
echo "make .circleci/config.yml"
mkdir -p .circleci
cat <<EOF >.circleci/config.yml
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
            curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-Linux-x86_64 > ~/docker-compose
            chmod +x ~/docker-compose
            sudo mv ~/docker-compose /usr/local/bin/docker-compose
      - run:
          name: docker-compose up --build -d
          command: docker-compose up --build -d
      - run: sleep 30
      - run:
          name: docker-compose exec app rails db:create
          command: docker-compose exec app rails db:create
      - run:
          name: docker-compose exec app rails db:migrate
          command: docker-compose exec app rails db:migrate
      - run:
          name: docker-compose exec app bash -c "yes n | rails webpacker:install"
          command: docker-compose exec app bash -c "yes n | rails webpacker:install"
      - run:
          name: docker-compose exec app rails webpacker:compile RAILS_ENV=test
          command: docker-compose exec app rails webpacker:compile RAILS_ENV=test
      - run:
          name: docker-compose exec app rspec
          command: docker-compose exec app rspec
      - run:
          name: docker-compose down
          command: docker-compose down

orbs:
  aws-ecr: circleci/aws-ecr@6.0.0
  aws-ecs: circleci/aws-ecs@0.0.8

workflows:
  test-and-deploy:
    jobs:
      - test

      - aws-ecr/build-and-push-image:
          name: web-build
          filters:
            branches:
              only: master
          requires:
            - test
          account-url: AWS_ECR_ACCOUNT_URL
          create-repo: true
          dockerfile: docker/web/Dockerfile
          repo: "ecstest-web"
          region: AWS_REGION
          tag: "\${CIRCLE_SHA1}"

      - aws-ecs/deploy-service-update:
          name: web-deploy
          requires:
            - web-build
          family: "ecstest-task"
          cluster-name: "ecstest-cluster"
          service-name: "ecstest-service"
          container-image-name-updates: "container=web,tag=\${CIRCLE_SHA1}"

      - aws-ecr/build-and-push-image:
          name: app-build
          filters:
            branches:
              only: master
          requires:
            - test
          account-url: AWS_ECR_ACCOUNT_URL
          create-repo: true
          dockerfile: docker/app/Dockerfile_production
          repo: "ecstest-app"
          region: AWS_REGION
          tag: "\${CIRCLE_SHA1}"

      - aws-ecs/deploy-service-update:
          name: app-deploy
          requires:
            - app-build
          family: "ecstest-task"
          cluster-name: "ecstest-cluster"
          service-name: "ecstest-service"
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
cat <<EOF >>src/Gemfile

gem "rspec-rails", group: [:test, :development]
gem "factory_bot_rails", group: :test
gem "rails-controller-testing", group: :test
EOF

cat src/Gemfile |
  sed "s/gem 'webdrivers'/# gem 'webdrivers'/" >__tmpfile__
cat __tmpfile__ >src/Gemfile
rm __tmpfile__

# test を削除
echo "rm -rf src/test"
rm -rf src/test

# database.yml を編集
echo "edit database.yml"
cat <<EOF >src/config/database.yml
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

# storage.yml を編集
echo "edit storage.yml"
cat <<EOF >>src/config/storage.yml

amazon:
  service: S3
  access_key_id: <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
  region: ${AWS_REGION}
  bucket: ${AWS_BUCKET}
EOF

# development.rb を編集
echo "edit development.rb"
cat src/config/environments/development.rb |
  sed "s/perform_caching = true/perform_caching = false/" |
  sed "s/enable_fragment_cache_logging = true/enable_fragment_cache_logging = false/" >__tmpfile__
cat __tmpfile__ >src/config/environments/development.rb
rm __tmpfile__

# production.rb を編集
echo "edit production.rb"
cat src/config/environments/production.rb |
  sed "s/config.assets.compile = false/config.assets.compile = true/" |
  sed "s/\# config.assets.css_compressor = :sass/config.assets.css_compressor = :sass/" |
  sed "s/config.active_storage.service = :local/config.active_storage.service = :amazon/" >__tmpfile__
cat __tmpfile__ >src/config/environments/production.rb
rm __tmpfile__

# webpacker.yml を編集
echo "edit webpacker.yml"
cat src/config/webpacker.yml |
  sed "s/check_yarn_integrity: true/check_yarn_integrity: false/" >__tmpfile__
cat __tmpfile__ >src/config/webpacker.yml
rm __tmpfile__

# puba.rb を編集
echo "edit puma.rb"
cat <<EOF >src/config/puma.rb
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
cat <<EOF >src/.gitignore
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
/public/packs/*
/public/packs-test/*
/node_modules
/yarn-error.log
yarn-debug.log*
.yarn-integrity
EOF

# rails_helper.rb を編集
echo "edit rails_helper.rb"
cat src/spec/rails_helper.rb |
  sed "s/\# Dir\[Rails.root/Dir\[Rails.root/" >__tmpfile__
cat __tmpfile__ >src/spec/rails_helper.rb
rm __tmpfile__

# application.rb を編集
echo "edit src/config/application.rb"
cat <<EOF >src/config/application.rb
equire_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HabitApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    config.hosts << ".example.com"
    config.hosts << "#{APP_DOMAIN}"
    config.hosts << Socket.ip_address_list.detect { |addr| addr.ipv4_private? }.ip_address
  end
end
EOF

# capybara.rb 作成
echo "mkdir -p src/spec/support "
mkdir -p src/spec/support
echo "edit src/spec/support/capybara.rb"
cat <<EOF >src/spec/support/capybara.rb
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, options: {
      browser: :remote,
      url: ENV.fetch("SELENIUM_DRIVER_URL"),
      desired_capabilities: :chrome
    }
    Capybara.server_host = Socket.ip_address_list.detect { |addr| addr.ipv4_private? }.ip_address
    Capybara.server_port = 3001
    host! "http://#{Capybara.server_host}:#{Capybara.server_port}"
  end
end
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

# ファイルの権限変更(3回目)
echo "sudo chown -R ${USER}:${GROUP} ."
sudo chown -R ${USER}:${GROUP} .

# 一度コンテナをリセット
echo "docker-compose down"
docker-compose down

# コンテナ起動
echo "docker-compose up"
docker-compose up
