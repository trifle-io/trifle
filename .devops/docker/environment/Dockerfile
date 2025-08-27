FROM debian:latest

ENV TZ=UTC
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
    libncurses5-dev \
    inotify-tools \
    tmux \
    htop \
    vim \
 && apt-get clean

#set the locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh || true
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/powerlevel10k
COPY .zshrc /root/.zshrc
COPY .p10k.zsh /root/p10k.zsh

#install asdf
ARG ASDF_VERSION
ARG TARGETPLATFORM
ENV ASDF_DATA_DIR="/root/.asdf"
ENV PATH="$ASDF_DATA_DIR/shims:$ASDF_DATA_DIR/bin:${PATH}"

RUN case ${TARGETPLATFORM} in \
        "linux/amd64") ASDF_ARCH="amd64" ;; \
        "linux/arm64") ASDF_ARCH="arm64" ;; \
        *) echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1 ;; \
    esac \
    && wget "https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz" \
    && tar -xf "asdf-${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz" \
    && chmod +x asdf \
    && mv asdf /usr/local/bin/ \
    && rm "asdf-${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz" \
    && mkdir -p "$ASDF_DATA_DIR" \
    && echo 'export ASDF_DATA_DIR="/root/.asdf"' >> /root/.bashrc \
    && echo 'export PATH="$ASDF_DATA_DIR/shims:$ASDF_DATA_DIR/bin:$PATH"' >> /root/.bashrc

RUN asdf plugin add erlang \
    && asdf plugin add elixir \
    && asdf plugin add ruby

# install erlang
ARG ERLANG_VERSION=28.0.2
ENV ERLANG_VERSION=${ERLANG_VERSION}
ENV KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac"
RUN asdf install erlang ${ERLANG_VERSION} \
    && asdf set --home erlang ${ERLANG_VERSION} \
    && asdf reshim erlang

# install elixir
ARG ELIXIR_VERSION=1.18.4
ENV ELIXIR_VERSION=${ELIXIR_VERSION}
RUN asdf install elixir ${ELIXIR_VERSION} \
    && asdf set --home elixir ${ELIXIR_VERSION} \
    && asdf reshim elixir

# install ruby
ARG RUBY_VERSION=3.2.0
ENV RUBY_VERSION=${RUBY_VERSION}
RUN asdf install ruby ${RUBY_VERSION} \
    && asdf set --home ruby ${RUBY_VERSION} \
    && asdf reshim ruby

RUN mix local.rebar --force \
    && mix local.hex --force

CMD ["zsh"]
