FROM python:3.13-slim

WORKDIR /app

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy project files
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/

# Install dependencies
RUN uv sync --frozen --no-dev

# Copy .env if present
COPY .env* ./

EXPOSE 8809

CMD ["uv", "run", "python", "-m", "swemo_mcp.server"]
