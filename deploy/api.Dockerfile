# Reborn API for hosted deploys (Render, Koyeb, Fly, a VPS). Build from the repo root:
#   docker build -f deploy/api.Dockerfile -t reborn-api .
# Unlike backend/Dockerfile it bakes in the card library and the media manifests, and
# deploy/api-start.sh imports the library on every start, so a deploy is all it takes
# to publish new cards.

FROM golang:1.26 AS build
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/reborn ./cmd/reborn

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/reborn /usr/local/bin/reborn
COPY content/library /content/library
COPY content/summaries /content/summaries
COPY content/explainers/out/manifest.json /content/explainers/manifest.json
COPY content/audio/out/manifest.json /content/audio/manifest.json
COPY deploy/api-start.sh /usr/local/bin/api-start
ENV ADDR=:8080 \
    CONTENT_DIR=/content/library \
    EXPLAINER_DIR=/content/explainers \
    CARD_AUDIO_DIR=/content/audio
EXPOSE 8080
CMD ["api-start"]
