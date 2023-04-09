FROM ubuntu:22.04 AS jekyll-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG en_US.UTF-8

RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    ruby-full \
    build-essential \
    zlib1g-dev

ENV GEM_HOME=/opt/gems
ENV PATH=/opt/gems/bin:$PATH

RUN gem install jekyll bundler

WORKDIR /blog
COPY Gemfile* /tmp/
RUN cd /tmp && bundle install