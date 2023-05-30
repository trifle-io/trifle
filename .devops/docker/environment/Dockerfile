FROM debian:latest

ENV TZ=Europe/Bratislava
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install ubuntu packages
RUN apt-get update -q \
 && apt-get install -y \
    build-essential \
    apt-transport-https \
    zsh \
    libpq-dev \
    git \
    curl \
    wget \
    unzip \
    gpg \
    gnupg2 \
    locales \
    autoconf \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libsqlite3-dev \
    libyaml-dev \
    libwxgtk-webview3.0-gtk3-dev \
    libncurses5-dev \
    inotify-tools \
    tmux \
    htop \
    vim \
 && apt-get clean

#set the locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
COPY .zshrc /root/.zshrc
COPY .p10k.zsh /root/p10k.zsh

#install asdf
ENV ASDF_ROOT /root/.asdf
ENV PATH "${ASDF_ROOT}/bin:${ASDF_ROOT}/shims:$PATH"
RUN git clone https://github.com/asdf-vm/asdf.git ${ASDF_ROOT} --branch v0.11.1

RUN asdf plugin-add ruby https://github.com/asdf-vm/asdf-ruby.git \
  && asdf plugin-add erlang https://github.com/asdf-vm/asdf-erlang.git \
  && asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git

# install ruby
ENV RUBY_VERSION 3.2.0
RUN asdf install ruby ${RUBY_VERSION} \
  && asdf global ruby ${RUBY_VERSION}

RUN gem install bundler

# install erlang
ENV ERLANG_VERSION 25.1.2
ENV KERL_CONFIGURE_OPTIONS "--disable-debug --without-javac"
RUN asdf install erlang ${ERLANG_VERSION} \
    && asdf global erlang ${ERLANG_VERSION}

# install elixir
ENV ELIXIR_VERSION 1.14.2
RUN asdf install elixir ${ELIXIR_VERSION} \
    && asdf global elixir ${ELIXIR_VERSION}

RUN mix local.rebar --force \
    && mix local.hex --force

CMD ["zsh"]
