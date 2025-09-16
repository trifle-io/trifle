# Production Dockerfile for Trifle
FROM trifle/environment:ruby_3.2.0-erlang_28.0.2-elixir_1.18.4 AS builder

# Set build environment
ENV MIX_ENV=prod

WORKDIR /app

# Copy mix files and install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application source code
COPY . .

# Build assets and compile the release
RUN mix assets.setup
RUN mix assets.deploy
RUN mix compile
RUN mix release

# Production stage
# Use Debian sid (unstable) for GLIBC >= 2.38 which Erlang/OTP 28 requires
FROM debian:latest AS runtime

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses6 \
    ca-certificates \
    curl \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd --create-home --shell /bin/bash app
USER app
WORKDIR /home/app

# Copy the built release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/trifle ./

# Set environment variables
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/api/health || exit 1

# Expose port
EXPOSE 4000

# Start the application
CMD ["./bin/trifle", "start"]
