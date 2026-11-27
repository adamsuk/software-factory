# Read-only factory dashboard (README.md, "Dashboard"). Build from the repo root:
#   docker compose up --build
# Standard library only; the one extra package is Debian's gh, for `gh api graphql`.
FROM docker.io/library/python:3.13-slim-trixie@sha256:e123d49d13f666b842ae2b925bf30703910481c67c89edc0a6b42e09d2b2168d

RUN apt-get update \
 && apt-get install -y --no-install-recommends gh ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 dashboard

WORKDIR /app
COPY dashboard/*.py dashboard/

USER dashboard
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1
EXPOSE 8787
ENTRYPOINT ["python3", "-m", "dashboard"]
CMD ["serve", "--host", "0.0.0.0", "--port", "8787"]
