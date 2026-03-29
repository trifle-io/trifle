FROM trifle/environment:ruby_3.2.0-erlang_28.0.2-elixir_1.18.4

# Install Chromium for server-side PDF/PNG exports in development too.
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      chromium \
      libgbm1 \
      libnss3 \
      fonts-liberation \
      fonts-noto \
      fonts-noto-color-emoji \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV CHROME_PATH=/usr/bin/chromium
